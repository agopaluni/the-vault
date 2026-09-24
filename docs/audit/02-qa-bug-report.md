# The Vault — QA Bug Report

**Build reviewed:** `main` @ `2e902e4` · **Date:** 2026-09-24
**Method:** A full read of all 47 Swift files (~7,200 lines), a look at the on-disk index and caches, the September screenshots, and a small Swift test to confirm the crash in BUG-01.

**Limits:** This was a static review. I could not click through the app, because this session has no Accessibility permission for native apps. Each bug has a confidence label:

- **Confirmed**: reproduced, or certain from the code path with no runtime dependency.
- **Likely**: the code path is clear, but the visible effect depends on runtime behavior (SwiftUI or AppKit internals, timing).
- **Possible**: needs unusual input or conditions to trigger.

**Severity scale:**
- **S1**: crash or data loss.
- **S2**: a core feature is broken or misleading.
- **S3**: a secondary feature is broken, or the UI is wrong.
- **S4**: cosmetic, or a minor inconsistency.

---

## Summary

| ID | Sev | Confidence | Title |
|---|---|---|---|
| BUG-01 | S1 | Confirmed | Indexing crashes on a video whose codec FourCC has a high-bit byte |
| BUG-02 | S1 | Confirmed | Corrupt or unreadable index → the next save overwrites the whole library with empty data |
| BUG-03 | S1 | Confirmed | "Re-index" destroys tags, AI analysis, review state and project membership for that source |
| BUG-04 | S1 | Confirmed | Sidebar "Remove Source" deletes a shared source from every project that uses it |
| BUG-05 | S1 | Confirmed | Edits made less than ~1s before quitting are lost (no save on terminate) |
| BUG-06 | S2 | Confirmed | Filters and sort do nothing in a project's Grid view (the main project screen) |
| BUG-07 | S2 | Confirmed | The "In Project" list drags only one file, and ⌘/⇧-click don't work there |
| BUG-08 | S2 | Confirmed | Claude billing, rate-limit and server errors fail silently; the run "completes" with no result |
| BUG-09 | S2 | Confirmed | Claude prompt only describes 6 of the 13 content tags |
| BUG-10 | S2 | Confirmed | Two Settings toggles do nothing (High-precision motion, Auto-enhance with AI) |
| BUG-11 | S2 | Confirmed | Ghost clips appear in All Media after deleting a project or source while it's indexing |
| BUG-12 | S2 | Confirmed | Deleted and moved files are never removed from the index |
| BUG-13 | S2 | Confirmed | Indexing several sources: the progress bar disappears after the first one, and auto-analyze starts early |
| BUG-14 | S3 | Confirmed | Sidebar project "Rename" is a no-op, and projects can't be renamed anywhere |
| BUG-15 | S3 | Confirmed | Batch mutations recompute the full filter and sort once per clip (quadratic slowdown) |
| BUG-16 | S3 | Confirmed | All Media and Untagged counts include project-only clips that All Media hides |
| BUG-17 | S3 | Confirmed | Project action buttons (Analyze, Enhance, ⋯) vanish whenever anything is selected |
| BUG-18 | S3 | Confirmed | Analysis and AI enhancement can't be cancelled |
| BUG-19 | S3 | Likely | Duplicate "View" menu in the menu bar; ⌘A likely hijacks text-field select-all |
| BUG-20 | S3 | Likely | Drag-to-reorder in the "In Project" list is probably disabled by `.onDrag` |
| BUG-21 | S3 | Likely | Thumbnail cache hits wait behind slow video thumbnail generation (scroll shimmer) |
| BUG-22 | S3 | Likely | The full-resolution photo preview decodes on the main thread (UI hitch on RAW/large files) |
| BUG-23 | S3 | Likely | Dropping folders on the Dock icon does nothing |
| BUG-24 | S3 | Possible | The audio analyzer can read past the end of a non-contiguous sample buffer |
| BUG-25 | S3 | Possible | Map "Fit" can raise an invalid-region exception for bad or globe-spanning GPS |
| BUG-26 | S4 | Confirmed | Filter chips show two chevrons each |
| BUG-27 | S4 | Confirmed | Clearing a source nickname in New Project creates a source with a blank name |
| BUG-28 | S4 | Confirmed | Only the last message is shown when adding several sources at once |
| BUG-29 | S4 | Confirmed | Enhancement error banner never clears |
| BUG-30 | S4 | Confirmed | Project item counts can include IDs of clips that no longer exist |
| BUG-31 | S4 | Confirmed | Keychain password prompt at every launch after a rebuild |

---

## S1: Crash and data loss

### BUG-01 · Indexing crashes on a video whose codec FourCC has a high-bit byte
**File:** `TheVault/Ingestion/MetadataExtractor.swift:153-158`

```swift
CChar((code >> 24) & 0xFF), ...
```
`CChar` is `Int8`. Converting a `UInt32` byte of 128 or more traps with *"Not enough bits to represent the passed value"*. **I reproduced this with a standalone Swift script.**

- **Trigger:** any video whose track format subtype has a byte ≥ 0x80. That means a corrupted file, an exotic or vendor codec, or a deliberately crafted file on an SD card.
- **Impact:** the app crashes mid-index. The file is never indexed, so it is retried on every scan. Each time that drive is mounted while the app is open, the app crashes again.
- **Fix:** build the string from `UInt8`s: `String(bytes: [...].map { UInt8(truncatingIfNeeded: $0) }, encoding: .macOSRoman)`, or use `CChar(truncatingIfNeeded:)`.
- **Related traps worth hardening in the same pass:**
  - `Int(abs(size.width))` at `MetadataExtractor.swift:119` traps on NaN or infinity.
  - `formattedDuration` does `Int(duration.rounded())`, which traps if duration is infinite (`CMTimeGetSeconds` returns +∞ for indefinite times).

### BUG-02 · Corrupt or unreadable index → the next save overwrites the whole library
**File:** `TheVault/Stores/LibraryStore.swift:99-122`

If `store.load()` throws, the store logs it and carries on with empty arrays. This happens after a partial write, a decode change in a future version, or a hand edit. The next mutation calls `scheduleSave()`, and `persist()` writes the empty snapshot over `VaultIndex.json`. Adding a source, tagging a clip or a geocode callback is enough to trigger it.

- **Impact:** every project, tag, analysis result and curation decision is gone, with no warning.
- **Fix:** on a load failure, copy the file to `VaultIndex.corrupt-<date>.json` and set a `loadFailed` flag. Refuse to persist until the user chooses "Start fresh" or "Restore backup". Also keep a rolling `VaultIndex.bak` before each write.

### BUG-03 · "Re-index" destroys curation data
**Files:** `LibraryStore.swift:446-452`, triggered from `SidebarView.swift:154`

`reindexSource` removes every item for the source, then re-walks it with an empty `existingPaths` set. The new items get **new UUIDs**, so:
- tags, analysis, review state (approved/discarded) and manual content tags are lost
- project `orderedItemIDs` point at IDs that no longer exist, so clips silently vanish from projects
- Claude results that cost credits are thrown away

**Fix:** re-walk without deleting first. The upsert path (`applyUpsert`, line 494) already matches on path and source and keeps user data. After the walk, prune items whose files are gone (see BUG-12).

### BUG-04 · Sidebar "Remove Source" deletes a shared source from every project
**Files:** `SidebarView.swift:158` → `LibraryStore.removeSource` (433)

Since the v4 shared-source model, one folder can back the browser *and* several projects. The browser's Sources section lists `globalSources`, which includes shared ones. "Remove Source" calls `removeSource`, which deletes the source and all its items, so the folder also disappears from every project and takes those projects' clips with it.

This is the exact behavior `detachSource` was written to prevent for the project side.

**Fix:** the sidebar should set `isGlobal = false` and call `removeSource` only if `isOrphaned`. Mirror `detachSource`. Add a confirmation that names the projects affected.

### BUG-05 · Edits made just before quitting are lost
**File:** `LibraryStore.swift:89-92, 223-229`

Saves are debounced by 1 second, then written on a background queue. Nothing flushes on `applicationWillTerminate`. The app also quits when its last window closes (`AppDelegate.swift:18`). So tagging a clip and hitting ⌘Q, or closing the window, within about a second loses the change. The async write can also be cut off mid-flight.

A secondary issue: `persist()` dispatches to the *concurrent* global queue. Two quick saves can land out of order, so an older snapshot is written last. This is rare with a 1-second debounce, but more likely on big libraries, where the pretty-printed, sorted-key JSON encode is slow.

**Fix:** add `func flush()`, which encodes and writes synchronously. Call it from `applicationWillTerminate` / `applicationShouldTerminate`. Route all writes through one serial queue. Drop `.prettyPrinted` and `.sortedKeys` for speed.

---

## S2: Core features broken or misleading

### BUG-06 · Filters and sort do nothing in a project's Grid view
**Files:** `ContentView.swift:77-89`, `ProjectView.swift:33, 317-324`

With a project selected in Grid mode, the centre pane is `ProjectView`. It reads `store.items(inProject:)` and `store.poolItems(forProject:)` directly and never uses `filteredItems`. The FilterBar and Sort menu stay on screen and still highlight as active, but have **no effect**. Meanwhile the status bar shows `filteredItems.count`, so it can disagree with what's on screen.

- **Repro:** open a project → Grid → set Videos, or a Date range → the list is unchanged.
- **Fix:** run the project's lists through `filter.matches` and `filter.areInOrder` (keeping manual order when sort is "Manual"). Otherwise hide the FilterBar in that view. Filtering is the better answer: it's where users most need it.

### BUG-07 · The "In Project" list drags only one file, and has no multi-select
**File:** `ProjectView.swift:266-283, 658`

The curated list still uses SwiftUI `.onDrag { MediaDrag.itemProvider(for: item) }`, the single-item path that was replaced everywhere else. Row taps set `selection = [item.id]`, so ⌘-click and ⇧-click don't work.

Dragging the project's selects, in project order, into Final Cut is the core use of this tab, and it delivers one clip.

**Fix:** use `.mediaDragSource(itemID:orderedIDs: items.map(\.id), store:)` on `ProjectRow`, and remove `onTapGesture`. For this tab, consider making drag order follow **project order** rather than pick order.

### BUG-08 · Claude errors other than 401 fail silently
**Files:** `AIEnrichmentService.swift:78-97`, `ClaudeContentTagger.swift:46-49`

Only `.invalidKey` is shown to the user. Every other failure (`case .failure: break`) is dropped. That includes:
- 400 "credit balance too low", the most likely error for a new user
- 429 rate limit
- 529 overloaded
- 5xx server errors
- network offline
- parse failures

- **Repro:** use a valid key on an account with $0 balance. The progress bar runs to "50/50", then nothing changes, and the button still says "Enhance with AI (50)".
- **Fix:**
  - Collect failures and show "12 of 50 clips failed: *credit balance too low*".
  - Stop the run on billing errors, as it already does for 401.
  - Retry 429 and 529 with backoff, honouring `retry-after`.
  - Treat `URLError.notConnectedToInternet` as fatal for the run.

### BUG-09 · Claude prompt only describes 6 of the 13 content tags
**File:** `ClaudeContentTagger.swift:79-91`

The JSON schema allows all 13 `ContentTag` values. The system prompt defines only talkingHead, bRoll, inMotion, driving, dialoguePresent and silent. It never mentions interview, closeUp, wideShot, landscape, establishing, action or music. So the model rarely returns them, and the richer tags added to the app are mostly unused by the AI tier. `dialoguePresent` and `silent` are also being guessed from still images; the model has no audio.

**Fix:** generate the tag glossary from `ContentTag.allCases`, adding a one-line definition per case. Drop the audio tags from the AI tier, or label them "implied".

### BUG-10 · Two Settings toggles do nothing
- **High-precision motion analysis** (`SettingsView.swift:36`): the flag reaches `OnDeviceAnalyzer.analyzeVideo(_:highPrecision:)`, but that parameter is never read. There is no optical-flow path.
- **Enhance new imports with AI automatically** (`SettingsView.swift:77`): `autoEnhanceWithAI` is saved but nothing reads it.

**Fix:** implement both, or remove them. A toggle that does nothing is worse than no toggle, especially one that implies spending money.

### BUG-11 · Ghost clips after deleting mid-index
**Files:** `LibraryStore.swift:490-512` (upsert), `278-279` (All Media filter)

Deleting a project or removing a source while `IngestionService` is still walking it doesn't cancel the walk. Later batches are upserted with a `sourceID` that no longer exists. The All Media filter hides only IDs in `projectOwnedSourceIDs`, which is built from sources that *still exist*, so these orphans **show up in All Media** with no source.

**Fix:** in `applyUpsert`, drop items whose `sourceID` isn't in `sources`. Add cancellation to `IngestionService` using a per-source token checked in the walk loop.

### BUG-12 · Deleted and moved files are never removed from the index
**File:** `IngestionService.swift:70-79`

Rescans (reconnect, re-add) only *add* files that aren't in `existingPaths`. Nothing removes items whose file is gone. After you clear an SD card and reuse it, the old clips stay in the library forever, and show "video.slash" thumbnails once the cache is evicted. Renamed or moved files appear twice.

**Fix:** at the end of a successful walk of an available source, mark items whose path wasn't seen as missing. Offer to "Remove N missing clips", or auto-prune clips that aren't in any project.

### BUG-13 · Multiple sources: the progress bar and auto-analyze fire early
**Files:** `LibraryStore.swift:476-484, 842-849`

`isIndexing` is a single boolean. Adding three folders queues three walks on the serial ingestion queue. The first `ingestionDidFinish` sets `isIndexing = false`, so the status bar goes idle while two sources are still indexing. If auto-analyze is on, it runs over a partial set.

**Fix:** keep a count of pending sources, or a `Set<UUID>`, and finish when it reaches zero.

---

## S3: Secondary features

### BUG-14 · Projects can't be renamed
`SidebarView.swift:164`: `Button("Rename") { /* ... placeholder */ }`. `LibraryStore.renameProject` exists but nothing calls it. The same is true for project type.

### BUG-15 · Batch mutations are quadratic
**File:** `LibraryStore.swift:24`

`items` has `didSet { refreshFiltered() }`. Every `items[idx].x = …` inside a loop triggers a full filter and sort, plus an `objectWillChange` publish. This affects `applyTag`, `removeTag`, `setReviewState`, `addItems`, `removeItems`, `clearProjectMembers`, the geocode callbacks (one per clip) and the per-clip analysis and enrichment callbacks.

Tagging 500 clips means 500 filter-and-sort passes over the whole library. It already stutters at your 504 clips and will get much worse at 5k.

**Fix:** wrap these loops in `bulkUpdate {}`. Batch the delegate callbacks, for example by coalescing geocode and analysis results every 250 ms.

### BUG-16 · Sidebar counts don't match what's shown
`SidebarView.swift:49-51` shows `store.items.count` for All Media and counts every untagged item. But All Media *hides* project-only sources (`computeFilteredItems`, line 278), while the `.untagged` scope doesn't. The number on the row, the number of clips shown, and the scopes themselves disagree.

### BUG-17 · Project actions disappear when anything is selected
`ProjectView.swift:99-112` wraps Analyze, Enhance with AI and the ⋯ menu in `if store.selection.isEmpty`. Selecting one clip to look at it removes the project's main buttons. With no hint that selection hides them, it reads as a glitch. (There is also no "Enhance selected".)

### BUG-18 · Long jobs can't be cancelled
`AnalysisService.cancelAll()` exists but is never called. `AIEnrichmentService` has no cancel at all. A 500-clip analysis, or a credit-spending enhancement, has to run to the end or the user has to quit the app. The `cancelled` flag is also read and written across threads without synchronization.

### BUG-19 · Duplicate "View" menu; ⌘A conflict
`TheVaultApp.swift:60` uses `CommandMenu("View")`, which *adds* a second menu next to the system View menu. It's visible in every screenshot (`File Edit View View Selection`).

Its "Select All ⌘A" also clashes with the standard Edit ▸ Select All. Since ⌘A selects media (you confirmed this earlier), ⌘A inside the Location field, the rename sheet or the API-key field very likely selects clips instead of text.

**Fix:** use `CommandGroup(after: .toolbar)` for the view modes. For ⌘A, use `CommandGroup(replacing: .textEditing)` / `.pasteboard`, and forward to the text field when a field editor is first responder.

### BUG-20 · Drag-to-reorder in "In Project" probably doesn't work
On macOS, attaching `.onDrag` to `List` rows generally replaces the List's built-in move-drag, so `.onMove` never fires. This needs a runtime check. If it's confirmed, reorder needs a drag handle or an explicit "Move up / down" path. Fixing BUG-07 changes this code anyway.

### BUG-21 · Thumbnail cache hits wait behind video generation
`ThumbnailService` is an `actor`, and it does synchronous `AVAssetImageGenerator.copyCGImage` and disk reads *inside* the actor. Every request, including memory-cache hits, waits behind whatever slow generation is running. Scrolling back to already-seen cells can flash shimmer. `load()` also resets `image = nil` first, which forces the flash.

**Fix:** check `NSCache` outside the actor (it's thread-safe), and generate in a detached task with limited concurrency.

### BUG-22 · Full-resolution photo decodes on the main thread
`DetailPanel.swift:127`: `NSImage(contentsOf: item.url)` runs in a `.task` on a view, which is main-actor, and decodes the whole original. A 60 MP RAW or a large HEIC will hitch the UI and use hundreds of MB. Use a 2048-px `CGImageSourceCreateThumbnailAtIndex` off the main actor.

### BUG-23 · Dropping folders on the Dock icon does nothing
- `AppDelegate.application(_:open:)` posts a notification that only `ContentView` listens for. On the Home screen, which is where the app launches, nobody receives it.
- The generated Info.plist declares no `CFBundleDocumentTypes` for folders, so the Dock probably won't accept the drop in the first place.

### BUG-24 · The audio analyzer can read past a buffer
`AudioAnalyzer.swift:59-67` calls `CMBlockBufferGetDataPointer(atOffset: 0)` and then reads `totalLength` bytes. The pointer is only valid for `lengthAtOffset` bytes. If the block buffer is non-contiguous, this reads out of bounds.

PCM output from `AVAssetReader` is usually contiguous, so this is Possible, not Likely. The fix is small: `CMBlockBufferCopyDataBytes` into a `[Float]`.

### BUG-25 · Map "Fit" can crash
`MapBrowserView.swift:75-89` pads the span by 1.4× without clamping. A latitude spread over ~128°, a longitude spread over ~257°, or a malformed coordinate (ISO-6709 parse of a bad string gives |lat| > 90) produces an invalid `MKCoordinateRegion`. MapKit raises `NSInvalidArgumentException` for those.

**Fix:** clamp the span to 180/360. Drop coordinates outside ±90/±180 at extraction time.

---

## S4: Cosmetic and minor

- **BUG-26:** Every filter chip renders `⌄ Orientation ⌄`. `.menuStyle(.borderlessButton)` adds its own indicator on top of the custom chevron. Add `.menuIndicator(.hidden)`. It's visible in `02-project-grid.png`.
- **BUG-27:** In `NewProjectSheet.create()`, an emptied nickname is passed as `""`, not `nil`, so the source has a blank label. Fall back to the default label.
- **BUG-28:** `sourceMessage` is a single string. Adding three folders with duplicates or errors shows only the last message.
- **BUG-29:** `enhancementError` is only cleared when a new run starts. The red banner stays until then, even after the key is fixed.
- **BUG-30:** Sidebar and project-card counts use `orderedItemIDs.count`, which includes dangling IDs (see BUG-03 and BUG-04). Count the resolved items instead, or prune IDs on removal.
- **BUG-31:** `AppSettings.init` reads the Keychain at launch. With ad-hoc signing, every rebuild changes the code signature, so macOS asks for the login password at launch. Read lazily: store a "has key" flag in UserDefaults and touch the Keychain only on Save or Enhance.

---

## Test gaps

There are no unit or UI tests in the repo. The highest-value first tests are pure logic that needs no UI:

1. `MediaFilter.matches` / `areInOrder`: date inclusivity, combined filters, nil handling.
2. Store migrations v2→v3→v4 against fixture JSON (the backup `VaultIndex.pre-v4-backup.json` is a ready-made fixture).
3. `LibraryStore` source lifecycle: add, attach, detach, remove, re-index. Assert that tags, analysis and membership survive. This would have caught BUG-03 and BUG-04.
4. `MetadataExtractor` fed a directory of malformed files (truncated MOV, zero-byte JPG, odd FourCC). This would have caught BUG-01.
5. Load failure: assert the index is never overwritten (BUG-02).
