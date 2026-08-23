//
//  LibraryStore.swift
//  The Vault
//
//  The single source of truth for app state, observed by the entire UI.
//  Holds the index (sources / items / projects / tags), the active filter and
//  selection, and drives persistence + ingestion. Mutations are debounced to
//  disk so a 10k-item library stays responsive.
//
//  All published state lives on the main actor; heavy work (indexing,
//  thumbnailing, geocoding) is delegated to background services.
//

import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class LibraryStore: ObservableObject {

    // MARK: Index
    @Published private(set) var sources: [Source] = [] { didSet { refreshFiltered() } }
    @Published private(set) var items: [MediaItem] = [] { didSet { refreshFiltered() } }
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tags: [Tag] = []

    // MARK: UI state
    @Published var filter = MediaFilter() { didSet { refreshFiltered() } }
    @Published var selection: Set<UUID> = [] { didSet { reconcileSelectionOrder() } }

    /// Selection in the order the user picked it — drives drag-out ordering so
    /// clips land on an NLE timeline first-picked → last-picked.
    @Published private(set) var selectionOrder: [UUID] = []
    @Published var detailItemID: UUID?
    @Published var sidebarSelection: SidebarSelection = .allMedia { didSet { refreshFiltered() } }
    @Published var viewMode: BrowserViewMode = .grid

    // MARK: Navigation (projects-first)
    @Published var route: AppRoute = .home

    /// When a project is selected, whether the timeline/map show the curated
    /// selection or every clip from the project's sources.
    @Published var projectScope: ProjectScope = .inProject { didSet { refreshFiltered() } }

    /// Transient message shown when a source can't be added (e.g. duplicate).
    @Published var sourceMessage: String?

    // MARK: Indexing progress
    @Published var isIndexing = false
    @Published var indexingProgress: Double = 0
    @Published var indexingStatusText: String = ""

    // MARK: On-device analysis progress
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var analysisStatusText: String = ""

    // MARK: AI enrichment (Stage B — Claude) progress
    @Published var isEnhancing = false
    @Published var enhancementProgress: Double = 0
    @Published var enhancementStatusText: String = ""
    @Published var enhancementError: String?

    /// Mirrored from AppSettings by the UI. Analysis is now user-triggered by
    /// default, so this is off unless the user opts in.
    var autoAnalyzeOnImport = false
    var highPrecisionMotion = false

    private let store: JSONVaultStore
    private let ingestion: IngestionService
    private let analysisService: AnalysisService
    private let enrichmentService: AIEnrichmentService
    private var saveCancellable: AnyCancellable?
    private let saveSubject = PassthroughSubject<Void, Never>()

    // Fast lookup by id, rebuilt on mutation.
    private var itemIndex: [UUID: Int] = [:]

    init(store: JSONVaultStore = JSONVaultStore()) {
        self.store = store
        self.ingestion = IngestionService()
        self.analysisService = AnalysisService()
        self.enrichmentService = AIEnrichmentService()
        self.ingestion.delegate = self
        self.analysisService.delegate = self
        self.enrichmentService.delegate = self

        // Debounce persistence so rapid edits coalesce into one write.
        saveCancellable = saveSubject
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persist() }

        loadFromDisk()
    }

    // MARK: - Loading & persistence

    private func loadFromDisk() {
        do {
            let snapshot = try store.load()
            self.sources = snapshot.sources
            self.items = snapshot.items
            self.projects = snapshot.projects
            self.tags = snapshot.tags.isEmpty ? Tag.defaults : snapshot.tags
            // One-time cleanup: clear previously auto-flagged wind noise (it was
            // unreliable) so users don't have to re-analyze to drop false flags.
            for i in items.indices where items[i].analysis?.flags.contains(.windNoise) == true {
                items[i].analysis?.flags.remove(.windNoise)
            }
            rebuildIndex()
            bulkUpdate {
                if snapshot.version < 3 { migrateToExplicitMembership() }
                if snapshot.version < 4 { migrateToSharedSources() }
            }
            refreshSourceAvailability()
            refreshFiltered()
        } catch {
            NSLog("The Vault: failed to load index — \(error.localizedDescription)")
            self.tags = Tag.defaults
        }
    }

    /// v2 → v3: membership used to be derived from source ownership. Bring those
    /// implied members across as explicit ones so existing projects keep their
    /// contents; from here on the user curates additions themselves.
    private func migrateToExplicitMembership() {
        for pIdx in projects.indices {
            let projectID = projects[pIdx].id
            let ownedSourceIDs = Set(sources.filter { $0.projectIDs.contains(projectID) }.map(\.id))
            guard !ownedSourceIDs.isEmpty else { continue }
            let implied = items
                .filter { ownedSourceIDs.contains($0.sourceID) }
                .sorted { ($0.captureDate ?? .distantPast) > ($1.captureDate ?? .distantPast) }
            for item in implied {
                projects[pIdx].add(item.id)
                if let iIdx = itemIndex[item.id] { items[iIdx].projectIDs.insert(projectID) }
            }
        }
        scheduleSave()
    }

    /// v3 → v4: a folder used to be indexed once per scope, so adding the same
    /// folder to both the browser and a project produced two sources and two
    /// copies of every file. Merge duplicate sources by path and fold their
    /// items together, preserving tags, analysis, review state, and membership.
    private func migrateToSharedSources() {
        // 1. Merge sources that point at the same folder.
        var survivorByPath: [String: Int] = [:]      // canonical path -> index
        var sourceRemap: [UUID: UUID] = [:]          // dropped source -> survivor
        var droppedSourceIDs = Set<UUID>()

        for (idx, source) in sources.enumerated() {
            let key = source.canonicalPath
            guard let survivorIdx = survivorByPath[key] else {
                survivorByPath[key] = idx
                continue
            }
            sources[survivorIdx].projectIDs.formUnion(source.projectIDs)
            sources[survivorIdx].isGlobal = sources[survivorIdx].isGlobal || source.isGlobal
            if sources[survivorIdx].bookmarkData == nil {
                sources[survivorIdx].bookmarkData = source.bookmarkData
            }
            sourceRemap[source.id] = sources[survivorIdx].id
            droppedSourceIDs.insert(source.id)
        }
        guard !droppedSourceIDs.isEmpty else { return }

        sources.removeAll { droppedSourceIDs.contains($0.id) }
        for i in items.indices {
            if let survivor = sourceRemap[items[i].sourceID] { items[i].sourceID = survivor }
        }

        // 2. Fold duplicate items (same file, same source) into one.
        var keptByKey: [String: Int] = [:]           // "sourceID|path" -> index
        var itemRemap: [UUID: UUID] = [:]            // dropped item -> kept item
        var droppedItemIDs = Set<UUID>()

        for (idx, item) in items.enumerated() {
            let key = "\(item.sourceID.uuidString)|\(item.url.standardizedFileURL.path)"
            guard let keptIdx = keptByKey[key] else {
                keptByKey[key] = idx
                continue
            }
            items[keptIdx].tagIDs.formUnion(item.tagIDs)
            items[keptIdx].projectIDs.formUnion(item.projectIDs)
            if items[keptIdx].analysis == nil { items[keptIdx].analysis = item.analysis }
            else if items[keptIdx].analysis?.apiModel == nil, item.analysis?.apiModel != nil {
                items[keptIdx].analysis = item.analysis      // prefer AI-enriched
            }
            if items[keptIdx].reviewState == nil { items[keptIdx].reviewState = item.reviewState }
            if let extra = item.userContentTags {
                items[keptIdx].userContentTags = (items[keptIdx].userContentTags ?? []).union(extra)
            }
            if let extra = item.suppressedContentTags {
                items[keptIdx].suppressedContentTags = (items[keptIdx].suppressedContentTags ?? []).union(extra)
            }
            itemRemap[item.id] = items[keptIdx].id
            droppedItemIDs.insert(item.id)
        }

        if !droppedItemIDs.isEmpty {
            items.removeAll { droppedItemIDs.contains($0.id) }
            // 3. Repoint project ordering at surviving items, keeping order.
            for p in projects.indices {
                var seen = Set<UUID>()
                projects[p].orderedItemIDs = projects[p].orderedItemIDs
                    .map { itemRemap[$0] ?? $0 }
                    .filter { seen.insert($0).inserted }
            }
            selection = Set(selection.map { itemRemap[$0] ?? $0 })
        }

        rebuildIndex()
        refreshSourceCounts()
        NSLog("The Vault: merged %d duplicate source(s) and %d duplicate item(s)",
              droppedSourceIDs.count, droppedItemIDs.count)
        scheduleSave()
    }

    private func scheduleSave() { saveSubject.send(()) }

    private func persist() {
        let snapshot = VaultSnapshot(sources: sources, items: items,
                                     projects: projects, tags: tags)
        DispatchQueue.global(qos: .utility).async { [store] in
            try? store.save(snapshot)
        }
    }

    private func rebuildIndex() {
        itemIndex = Dictionary(uniqueKeysWithValues:
            items.enumerated().map { ($0.element.id, $0.offset) })
    }

    // MARK: - Derived data

    /// Items passing the active filter, sorted. CACHED — recomputing this on
    /// every SwiftUI body evaluation (and once per cell, in the timeline) was
    /// O(n²) per frame and made scrolling jump. Recomputed only when its inputs
    /// change, via `refreshFiltered()`.
    @Published private(set) var filteredItems: [MediaItem] = []

    /// The item IDs currently on screen, in display order. Views publish this so
    /// ⌘A selects exactly what's visible, in the order it's shown (e.g. timeline
    /// order). Not @Published — nothing observes it, avoiding render loops.
    private(set) var visibleItemIDs: [UUID] = []

    func setVisibleItems(_ ids: [UUID]) {
        guard ids != visibleItemIDs else { return }
        visibleItemIDs = ids
    }

    /// Suppresses cache rebuilds during bulk mutations (ingest batches, etc.).
    private var suspendFilterRefresh = false

    func refreshFiltered() {
        guard !suspendFilterRefresh else { return }
        filteredItems = computeFilteredItems()
    }

    /// Run a batch of mutations, rebuilding the filtered cache once at the end.
    private func bulkUpdate(_ body: () -> Void) {
        suspendFilterRefresh = true
        body()
        suspendFilterRefresh = false
        refreshFiltered()
    }

    private func computeFilteredItems() -> [MediaItem] {
        var working = items

        // Sidebar scope first.
        switch sidebarSelection {
        case .allMedia:
            // The browser shows only global-source media; project-owned footage
            // lives inside its project, not here.
            let projectOwned = projectOwnedSourceIDs
            working = working.filter { !projectOwned.contains($0.sourceID) }
        case .source(let id): working = working.filter { $0.sourceID == id }
        case .project(let id):
            switch projectScope {
            case .inProject:
                working = working.filter { isMember($0, ofProject: id) }
            case .sourceMedia:
                let owned = Set(sources(ownedBy: id).map(\.id))
                working = working.filter { owned.contains($0.sourceID) }
            }
        case .untagged: working = working.filter { $0.tagIDs.isEmpty }
        case .tag(let id): working = working.filter { $0.tagIDs.contains(id) }
        }

        working = working.filter { filter.matches($0) }
        working.sort { filter.areInOrder($0, $1) }
        return working
    }

    /// Source IDs hidden from the global browser (project-only sources).
    private var projectOwnedSourceIDs: Set<UUID> {
        Set(sources.filter { !$0.isGlobal }.map(\.id))
    }

    /// Membership is explicit — the user curates which pool clips are in the
    /// project (see the project's "Source Media" view).
    func isMember(_ item: MediaItem, ofProject projectID: UUID) -> Bool {
        item.projectIDs.contains(projectID)
    }

    func item(_ id: UUID) -> MediaItem? {
        guard let idx = itemIndex[id], idx < items.count else { return nil }
        return items[idx]
    }

    var selectedItems: [MediaItem] {
        selection.compactMap { item($0) }
    }

    var totalFilteredSize: Int64 {
        filteredItems.reduce(0) { $0 + $1.fileSize }
    }

    /// Distinct camera labels across the whole library (for the filter UI).
    var availableCameras: [String] {
        Set(items.map(\.cameraLabel)).sorted()
    }

    var availableFormats: [String] {
        Set(items.map(\.fileFormat)).filter { !$0.isEmpty }.sorted()
    }

    func tag(_ id: UUID) -> Tag? { tags.first { $0.id == id } }
    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }
    func source(_ id: UUID) -> Source? { sources.first { $0.id == id } }

    // MARK: - Sources

    /// Sources shown in the browser.
    var globalSources: [Source] { sources.filter(\.isGlobal) }

    /// Sources attached to a project.
    func sources(ownedBy projectID: UUID) -> [Source] {
        sources.filter { $0.projectIDs.contains(projectID) }
    }

    /// True if this folder is already attached to the given scope.
    func sourceExists(at url: URL, ownerProject: UUID? = nil) -> Bool {
        let target = url.standardizedFileURL.path
        guard let existing = sources.first(where: { $0.canonicalPath == target }) else { return false }
        if let ownerProject { return existing.projectIDs.contains(ownerProject) }
        return existing.isGlobal
    }

    /// Add a source folder. `ownerProject` nil = a browser source; set = attach
    /// it to that project.
    ///
    /// A folder is only ever indexed ONCE: if a source already covers this
    /// path, it is *attached* to the requested scope and its existing media is
    /// reused, rather than creating a duplicate source and re-indexing every
    /// file. Returns the source (new or existing), or nil if it was already
    /// attached to this exact scope.
    @discardableResult
    func addSource(url: URL, label: String? = nil, ownerProject projectID: UUID? = nil) -> Source? {
        let target = url.standardizedFileURL.path

        if let idx = sources.firstIndex(where: { $0.canonicalPath == target }) {
            let alreadyAttached = projectID.map { sources[idx].projectIDs.contains($0) }
                ?? sources[idx].isGlobal
            if alreadyAttached {
                sourceMessage = "“\(sources[idx].label)” is already added."
                return nil
            }
            // Reuse the existing index — attach, don't re-scan.
            if let projectID { sources[idx].projectIDs.insert(projectID) }
            else { sources[idx].isGlobal = true }
            let reused = sources[idx]
            sourceMessage = "“\(reused.label)” was already indexed — reusing its "
                + "\(reused.indexedItemCount) clips instead of scanning again."
            scheduleSave()
            // Pick up anything added to the folder since the last scan.
            if reused.isAvailable { index(source: reused) }
            return reused
        }

        // Capture a security-scoped bookmark for persistent access.
        let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        let mediaType = Source.guessMediaType(for: url)
        let resolvedLabel = label ?? defaultLabel(for: url, mediaType: mediaType)
        let source = Source(label: resolvedLabel,
                            path: url.path,
                            bookmarkData: bookmark,
                            mediaType: mediaType,
                            volumeName: Source.volumeName(for: url),
                            projectIDs: projectID.map { [$0] } ?? [],
                            isGlobal: projectID == nil)
        sources.append(source)
        scheduleSave()
        index(source: source)
        return source
    }

    /// Detach a source from a project. The source (and its index) survives if
    /// the browser or another project still uses it.
    func detachSource(_ sourceID: UUID, fromProject projectID: UUID) {
        guard let idx = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[idx].projectIDs.remove(projectID)
        let orphaned = sources[idx].isOrphaned
        // Drop this project's membership for that source's clips.
        let clipIDs = Set(items.filter { $0.sourceID == sourceID }.map(\.id))
        removeItems(clipIDs, fromProject: projectID)
        if orphaned { removeSource(sourceID) } else { scheduleSave() }
    }

    /// Add a project-owned source (used by the project view's source manager).
    @discardableResult
    func addProjectSource(_ projectID: UUID, url: URL, label: String? = nil) -> Source? {
        addSource(url: url, label: label, ownerProject: projectID)
    }

    private func defaultLabel(for url: URL, mediaType: SourceMediaType) -> String {
        let folder = url.lastPathComponent
        return "\(folder) - \(mediaType.defaultLabel)"
    }

    func renameSource(_ id: UUID, to label: String) {
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[idx].label = label
        scheduleSave()
    }

    /// Removes a source and all its indexed items (originals are untouched).
    func removeSource(_ id: UUID) {
        sources.removeAll { $0.id == id }
        let removed = items.filter { $0.sourceID == id }.map(\.id)
        items.removeAll { $0.sourceID == id }
        // Clean references from projects.
        for i in projects.indices {
            projects[i].orderedItemIDs.removeAll { removed.contains($0) }
        }
        rebuildIndex()
        selection.subtract(removed)
        scheduleSave()
    }

    func reindexSource(_ id: UUID) {
        guard let source = source(id) else { return }
        // Drop existing items for this source, then re-walk.
        items.removeAll { $0.sourceID == id }
        rebuildIndex()
        index(source: source)
    }

    /// Re-checks which sources are currently mounted/available (hot-plug).
    /// Disconnected sources stay in place (greyed out); their indexed items and
    /// cached thumbnails remain visible. When a source reconnects it is
    /// re-scanned for new files — no re-adding required.
    func refreshSourceAvailability() {
        let fm = FileManager.default
        var reconnected: [Source] = []
        for i in sources.indices {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: sources[i].path, isDirectory: &isDir)
            let nowAvailable = exists && isDir.boolValue
            if nowAvailable && !sources[i].isAvailable {
                reconnected.append(sources[i])   // offline → online
            }
            sources[i].isAvailable = nowAvailable
        }
        // Pick up any new files added while disconnected (existing items kept).
        for source in reconnected { index(source: source) }
    }

    // MARK: - Ingestion

    private func index(source: Source) {
        isIndexing = true
        indexingProgress = 0
        indexingStatusText = "Scanning \(source.label)…"
        // Only skip files already indexed for THIS source (so the same folder
        // can populate a project source even if a global source also has it).
        let existing = Set(items.filter { $0.sourceID == source.id }.map(\.path))
        ingestion.index(source: source, existingPaths: existing)
    }

    private func upsert(_ newItems: [MediaItem]) {
        bulkUpdate { applyUpsert(newItems) }
    }

    private func applyUpsert(_ newItems: [MediaItem]) {
        for item in newItems {
            if let idx = itemIndex[item.id] {
                items[idx] = item
            } else if let idx = items.firstIndex(where: { $0.path == item.path && $0.sourceID == item.sourceID }) {
                // Same file re-indexed for the SAME source (reconnect / re-scan):
                // preserve tags, project membership, AI analysis, review state.
                var merged = item
                merged.tagIDs = items[idx].tagIDs
                merged.projectIDs = items[idx].projectIDs
                merged.analysis = items[idx].analysis
                merged.reviewState = items[idx].reviewState
                merged.userContentTags = items[idx].userContentTags
                merged.suppressedContentTags = items[idx].suppressedContentTags
                items[idx] = merged
            } else {
                items.append(item)
            }
        }
        rebuildIndex()
        refreshSourceCounts()
        scheduleSave()
    }

    private func refreshSourceCounts() {
        var counts: [UUID: Int] = [:]
        for item in items { counts[item.sourceID, default: 0] += 1 }
        for i in sources.indices { sources[i].indexedItemCount = counts[sources[i].id] ?? 0 }
    }

    // MARK: - On-device analysis

    /// IDs of currently-available sources (so we don't try to read ejected drives).
    private var availableSourceIDs: Set<UUID> {
        Set(sources.filter(\.isAvailable).map(\.id))
    }

    func items(inSource sourceID: UUID) -> [MediaItem] {
        items.filter { $0.sourceID == sourceID }
    }

    /// Items eligible to analyze right now (available source; unanalyzed unless forced).
    func analyzableCount(_ itemIDs: Set<UUID>, force: Bool) -> Int {
        let available = availableSourceIDs
        return itemIDs.compactMap { item($0) }
            .filter { available.contains($0.sourceID) && (force || $0.needsAnalysis) }
            .count
    }

    /// Analyze every item that still needs it (new or re-encoded media).
    func analyzePendingItems() {
        guard !isAnalyzing else { return }
        let available = availableSourceIDs
        let pending = items.filter { $0.needsAnalysis && available.contains($0.sourceID) }
        startAnalysis(pending)
    }

    /// Run the on-device pass over a chosen set. `force` re-analyzes already-done
    /// clips; otherwise only clips that still need it are processed. This is the
    /// user-triggered entry point (Analyze Selected / Source / All).
    func analyze(_ itemIDs: Set<UUID>, force: Bool = false) {
        guard !isAnalyzing else { return }
        let available = availableSourceIDs
        let targets = itemIDs.compactMap { item($0) }
            .filter { available.contains($0.sourceID) && (force || $0.needsAnalysis) }
        startAnalysis(targets)
    }

    /// Back-compat alias used by earlier review UI — forces re-analysis.
    func analyzeItems(_ itemIDs: Set<UUID>) { analyze(itemIDs, force: true) }

    func analyzeSource(_ sourceID: UUID, force: Bool = false) {
        analyze(Set(items(inSource: sourceID).map(\.id)), force: force)
    }

    private func startAnalysis(_ targets: [MediaItem]) {
        guard !isAnalyzing, !targets.isEmpty else { return }
        isAnalyzing = true
        analysisProgress = 0
        analysisService.analyze(items: targets, highPrecisionMotion: highPrecisionMotion)
    }

    // MARK: - AI enrichment (Stage B — spends Claude credits)

    /// Number of clips in `ids` that would actually be sent to the API (used to
    /// label the "Enhance with AI" button and confirm spend).
    func enrichmentCandidates(_ ids: Set<UUID>) -> [MediaItem] {
        ids.compactMap { item($0) }.filter { candidate in
            !candidate.isDiscarded &&
            !candidate.qualityFlags.contains { $0.isMistake } &&   // don't pay to tag mistakes
            (candidate.analysis?.apiModel == nil ||
             candidate.analysis?.fileFingerprint != candidate.analysisFingerprint)
        }
    }

    /// Run Claude content tagging over the eligible members of `ids`.
    func enhanceItems(_ ids: Set<UUID>, apiKey: String) {
        guard !isEnhancing, !apiKey.isEmpty else { return }
        let targets = enrichmentCandidates(ids)
        guard !targets.isEmpty else { return }
        enhancementError = nil
        isEnhancing = true
        enhancementProgress = 0
        enrichmentService.enrich(items: targets, apiKey: apiKey)
    }

    // MARK: - Review state (non-destructive; never deletes files)

    func setReviewState(_ state: ReviewState, for itemIDs: Set<UUID>) {
        for id in itemIDs where itemIndex[id] != nil {
            items[itemIndex[id]!].reviewState = state
        }
        scheduleSave()
    }

    func setContentTag(_ tag: ContentTag, on itemID: UUID, present: Bool) {
        guard let idx = itemIndex[itemID] else { return }
        var added = items[idx].userContentTags ?? []
        var suppressed = items[idx].suppressedContentTags ?? []
        if present { added.insert(tag); suppressed.remove(tag) }
        else { suppressed.insert(tag); added.remove(tag) }
        items[idx].userContentTags = added.isEmpty ? nil : added
        items[idx].suppressedContentTags = suppressed.isEmpty ? nil : suppressed
        scheduleSave()
    }

    // MARK: - Tags

    func createTag(name: String, colorHex: String, projectID: UUID? = nil) -> Tag {
        let tag = Tag(name: name, colorHex: colorHex, projectID: projectID)
        tags.append(tag)
        scheduleSave()
        return tag
    }

    func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        for i in items.indices { items[i].tagIDs.remove(id) }
        if filter.tagIDs.contains(id) { filter.tagIDs.remove(id) }
        scheduleSave()
    }

    /// Apply a tag to every item in `itemIDs` (batch tagging).
    func applyTag(_ tagID: UUID, to itemIDs: Set<UUID>) {
        for id in itemIDs {
            if let idx = itemIndex[id] { items[idx].tagIDs.insert(tagID) }
        }
        scheduleSave()
    }

    func removeTag(_ tagID: UUID, from itemIDs: Set<UUID>) {
        for id in itemIDs {
            if let idx = itemIndex[id] { items[idx].tagIDs.remove(tagID) }
        }
        scheduleSave()
    }

    func toggleTag(_ tagID: UUID, on itemID: UUID) {
        guard let idx = itemIndex[itemID] else { return }
        if items[idx].tagIDs.contains(tagID) { items[idx].tagIDs.remove(tagID) }
        else { items[idx].tagIDs.insert(tagID) }
        scheduleSave()
    }

    // MARK: - Projects

    @discardableResult
    func createProject(name: String, type: ProjectType) -> Project {
        let project = Project(name: name, type: type)
        projects.append(project)
        scheduleSave()
        return project
    }

    func deleteProject(_ id: UUID) {
        bulkUpdate {
            // Detach this project from its sources. A source is only removed if
            // nothing else uses it — a folder shared with the browser or another
            // project keeps its index. Originals on disk are never touched.
            for i in sources.indices { sources[i].projectIDs.remove(id) }
            let orphanedSourceIDs = Set(sources.filter(\.isOrphaned).map(\.id))
            sources.removeAll { orphanedSourceIDs.contains($0.id) }
            let removedItems = items.filter { orphanedSourceIDs.contains($0.sourceID) }.map(\.id)
            items.removeAll { orphanedSourceIDs.contains($0.sourceID) }
            selection.subtract(removedItems)

            projects.removeAll { $0.id == id }
            for i in items.indices { items[i].projectIDs.remove(id) }
            rebuildIndex()
            if case .project(let pid) = sidebarSelection, pid == id { sidebarSelection = .allMedia }
            scheduleSave()
        }
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].name = name
        projects[idx].updatedAt = Date()
        scheduleSave()
    }

    /// Add items to a project (and back-reference on each item).
    func addItems(_ itemIDs: Set<UUID>, toProject projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        for id in itemIDs {
            projects[pIdx].add(id)
            if let iIdx = itemIndex[id] { items[iIdx].projectIDs.insert(projectID) }
        }
        scheduleSave()
    }

    /// Remove every clip from a project, leaving its sources (and the pool)
    /// intact so the user can curate from scratch. Files are untouched.
    func clearProjectMembers(_ projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let ids = projects[pIdx].orderedItemIDs
        projects[pIdx].orderedItemIDs.removeAll()
        projects[pIdx].updatedAt = Date()
        for id in ids {
            if let iIdx = itemIndex[id] { items[iIdx].projectIDs.remove(projectID) }
        }
        scheduleSave()
    }

    func removeItems(_ itemIDs: Set<UUID>, fromProject projectID: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        for id in itemIDs {
            projects[pIdx].remove(id)
            if let iIdx = itemIndex[id] { items[iIdx].projectIDs.remove(projectID) }
        }
        scheduleSave()
    }

    /// Persist a new ordering for a project's members (drag to reorder).
    func reorderProject(_ projectID: UUID, to orderedIDs: [UUID]) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIdx].orderedItemIDs = orderedIDs
        projects[pIdx].updatedAt = Date()
        scheduleSave()
    }

    /// Members of a project — the curated selection, in saved order. Media from
    /// the project's sources is NOT automatically a member; the user picks from
    /// the pool (see `poolItems(forProject:)`) and adds explicitly.
    func items(inProject projectID: UUID) -> [MediaItem] {
        (project(projectID)?.orderedItemIDs ?? []).compactMap { item($0) }
    }

    /// Everything available to a project: all media from the sources it owns.
    /// This is the pool the user browses to add footage.
    func poolItems(forProject projectID: UUID) -> [MediaItem] {
        let ownedSourceIDs = Set(sources(ownedBy: projectID).map(\.id))
        guard !ownedSourceIDs.isEmpty else { return [] }
        return items
            .filter { ownedSourceIDs.contains($0.sourceID) }
            .sorted { ($0.captureDate ?? .distantPast) > ($1.captureDate ?? .distantPast) }
    }

    /// Pool clips not yet added to the project.
    func poolItemsNotInProject(_ projectID: UUID) -> [MediaItem] {
        poolItems(forProject: projectID).filter { !$0.projectIDs.contains(projectID) }
    }

    // MARK: - Selection helpers

    /// ⌘A — select everything currently on screen, in the order it's displayed
    /// (so a timeline selection drags out in timeline order).
    func selectAll() {
        selectAll(ids: visibleItemIDs.isEmpty ? filteredItems.map(\.id) : visibleItemIDs)
    }

    /// Select a specific ordered list, preserving that order for drag-out.
    func selectAll(ids: [UUID]) {
        selection = Set(ids)
        selectionOrder = ids
    }

    func clearSelection() { selection.removeAll(); selectionAnchor = nil }

    /// Keep `selectionOrder` in sync with any mutation of `selection`.
    private func reconcileSelectionOrder() {
        let current = selection
        selectionOrder.removeAll { !current.contains($0) }
        let known = Set(selectionOrder)
        for id in current where !known.contains(id) { selectionOrder.append(id) }
    }

    /// Items in pick order (for drag-out and ordered hand-off).
    var selectedItemsInOrder: [MediaItem] { selectionOrder.compactMap { item($0) } }

    /// URLs to drag when a drag starts on `id`: the whole ordered selection if
    /// that clip is part of it, otherwise just that clip.
    func dragURLs(startingFrom id: UUID) -> [URL] {
        let urls: [URL]
        if selection.contains(id), !selectionOrder.isEmpty {
            urls = selectionOrder.compactMap { item($0)?.url }
        } else {
            urls = item(id).map { [$0.url] } ?? []
        }
        // The same file can be indexed under two sources (e.g. a folder added
        // both to the browser and to a project) — don't hand the same path over
        // twice, order preserved.
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Anchor for shift-range selection (last plainly-clicked item).
    @Published var selectionAnchor: UUID?

    /// Unified click selection honoring ⌘ (toggle) and ⇧ (extend range).
    /// `ordered` is the currently-displayed item order, needed for ranges.
    func handleSelect(_ id: UUID, in ordered: [UUID],
                      modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags,
                      openDetail: Bool = true) {
        let mods = modifiers
        if mods.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            selectionAnchor = id
        } else if mods.contains(.shift),
                  let anchor = selectionAnchor ?? selectionOrder.last,
                  let a = ordered.firstIndex(of: anchor),
                  let b = ordered.firstIndex(of: id) {
            let range = a <= b ? a...b : b...a
            // Insert one at a time so selectionOrder follows display order.
            for rid in ordered[range] where !selection.contains(rid) { selection.insert(rid) }
            // anchor stays put so the range can be re-dragged
        } else {
            selection = [id]
            selectionAnchor = id
            if openDetail { detailItemID = id }
        }
    }

    /// URLs for the currently selected items (used by clipboard / Finder / drag).
    var selectedURLs: [URL] { selectedItems.map(\.url) }
}

// MARK: - IngestionServiceDelegate

extension LibraryStore: IngestionServiceDelegate {
    nonisolated func ingestion(_ service: IngestionService, didIndex batch: [MediaItem]) {
        Task { @MainActor in self.upsert(batch) }
    }

    nonisolated func ingestion(_ service: IngestionService,
                               didProgress fraction: Double, status: String) {
        Task { @MainActor in
            self.indexingProgress = fraction
            self.indexingStatusText = status
        }
    }

    nonisolated func ingestionDidFinish(_ service: IngestionService) {
        Task { @MainActor in
            self.isIndexing = false
            self.indexingStatusText = ""
            self.refreshSourceCounts()
            self.scheduleSave()
            if self.autoAnalyzeOnImport { self.analyzePendingItems() }
        }
    }

    nonisolated func ingestion(_ service: IngestionService,
                               didGeocode itemID: UUID, name: String) {
        Task { @MainActor in
            if let idx = self.itemIndex[itemID] {
                self.items[idx].locationName = name
                self.scheduleSave()
            }
        }
    }

    nonisolated func ingestion(_ service: IngestionService, didReport message: String) {
        Task { @MainActor in self.sourceMessage = message }
    }
}

// MARK: - AnalysisServiceDelegate

extension LibraryStore: AnalysisServiceDelegate {
    nonisolated func analysis(_ service: AnalysisService,
                              didAnalyze itemID: UUID, result: MediaAnalysis) {
        Task { @MainActor in
            if let idx = self.itemIndex[itemID] {
                self.items[idx].analysis = result
                self.scheduleSave()
            }
        }
    }

    nonisolated func analysis(_ service: AnalysisService,
                              didProgress fraction: Double, status: String) {
        Task { @MainActor in
            self.analysisProgress = fraction
            self.analysisStatusText = status
        }
    }

    nonisolated func analysisDidFinish(_ service: AnalysisService) {
        Task { @MainActor in
            self.isAnalyzing = false
            self.analysisStatusText = ""
        }
    }
}

// MARK: - AIEnrichmentDelegate

extension LibraryStore: AIEnrichmentDelegate {
    nonisolated func enrichment(_ service: AIEnrichmentService, didEnrich itemID: UUID,
                                tags: Set<ContentTag>, scene: String?, model: String) {
        Task { @MainActor in
            guard let idx = self.itemIndex[itemID] else { return }
            // Merge API tags into the existing (on-device) analysis, preserving
            // flags and scores. The result is a hybrid suggestion.
            var analysis = self.items[idx].analysis
                ?? MediaAnalysis(fileFingerprint: self.items[idx].analysisFingerprint)
            analysis.contentTags.formUnion(tags)
            analysis.source = analysis.flags.isEmpty && analysis.scores == nil ? .api : .hybrid
            analysis.apiModel = model
            analysis.sceneDescription = scene
            analysis.analyzedAt = Date()
            self.items[idx].analysis = analysis
            self.scheduleSave()
        }
    }

    nonisolated func enrichment(_ service: AIEnrichmentService,
                                didProgress fraction: Double, status: String) {
        Task { @MainActor in
            self.enhancementProgress = fraction
            self.enhancementStatusText = status
        }
    }

    nonisolated func enrichment(_ service: AIEnrichmentService, didFail message: String) {
        Task { @MainActor in self.enhancementError = message }
    }

    nonisolated func enrichmentDidFinish(_ service: AIEnrichmentService) {
        Task { @MainActor in
            self.isEnhancing = false
            self.enhancementStatusText = ""
        }
    }
}
