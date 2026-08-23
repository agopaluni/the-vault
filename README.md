# The Vault

A native macOS media organization and project-management tool for filmmakers and content creators who shoot across multiple cameras, devices, and storage sources.

Built with SwiftUI + AppKit. Dark-mode first — *Final Cut Pro meets Lightroom*.

> **Non-destructive by design.** The Vault only ever *reads* your originals. It never moves, modifies, or deletes source files. The index, thumbnails, and projects live in the app's own Application Support / Caches directories.

---

## Features

### Projects-first workflow
The app opens on a Home screen: **Create a New Project**, **Browse Existing Projects**, or **Video Browser**.

A project owns one or more **source folders** (SD card, SSD, internal or external drive). Those sources form a **pool** of available footage; the project itself is the **curated selection** you build from that pool. Sources can be nicknamed, and a project's sources are kept separate from the global browser's.

### AI-assisted logging (two tiers)

**Stage A — on-device, free, no API key.** Samples a handful of frames per clip and analyzes audio locally:

- *Mistake footage*: very short clips, accidental starts, black / lens-cap shots
- *Technical quality*: blur, shake severity, poor exposure, audio clipping, silence
- *Content tags*: talking head (via Vision face detection), B-roll, in-motion, speaking vs silent

**Stage B — Claude (optional, opt-in).** Sends 1–3 downsampled keyframes per clip to `claude-haiku-4-5` with Structured Outputs for richer content tagging and a short scene description. Gated to skip mistake footage and already-tagged clips, results cached by file fingerprint, and run only when you press **Enhance with AI** — so you control when credits are spent. The API key is stored in the macOS Keychain.

All AI output is a **suggestion**, stored alongside the clip and always overridable by hand. "Discard" hides a clip from view; it never touches the file.

### Browsing & review
- **Grid**, **Timeline** (grouped by capture day), and **Map** (GPS-plotted) views
- Stackable filters: media type, orientation, camera, format, date range, location, tags, content tags, quality flags, and AI-analysis state
- Flagged-footage triage with bulk approve / discard
- Detail panel with full-res photo zoom, inline video playback, complete metadata, and manual tag editing
- Finder-style multi-select (click / ⌘-click / ⇧-click / ⌘A)

### Drag & drop to your NLE
Multi-select and drag clips straight into Final Cut Pro, Premiere, Resolve, Lightroom, or Finder. Files transfer **in the order you selected them**, so they land on an NLE timeline in that order. Plus **Copy File Paths** and **Reveal in Finder**.

---

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15 or later (Xcode 26.6 used for development)

## Build

```bash
./build_and_install.sh
```

This regenerates the Xcode project, builds Release, and installs to `/Applications/The Vault.app`.

To build manually:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project TheVault.xcodeproj -target "The Vault" -configuration Release \
  SYMROOT=/tmp/vault_build build
```

The app ships **un-sandboxed** so it can read footage on any mounted volume without per-folder friction. To sandbox for the App Store, flip `com.apple.security.app-sandbox` in `TheVault/TheVault.entitlements`; the code already captures security-scoped bookmarks per source.

### Project file generation

`TheVault.xcodeproj/project.pbxproj` is generated from the source tree by `gen_pbxproj.py`. After adding or removing Swift files:

```bash
python3 gen_pbxproj.py
```

App icons are generated from a single square PNG:

```bash
./gen_appicon.sh path/to/logo.png
```

---

## Getting started

1. Launch and choose **Create a New Project**.
2. Add one or more source folders and give them nicknames.
3. Open the project's **Source Media** tab to see everything in the pool.
4. Select the clips you want and hit **Add to Project**.
5. Press **Analyze** to run the free on-device pass, and optionally **Enhance with AI** (requires a key in Settings ▸ Claude API).

If a source folder can't be read, grant The Vault access under **System Settings ▸ Privacy & Security ▸ Files and Folders** (or Full Disk Access) — most common for external drives and the Desktop/Documents/Downloads folders.

---

## Architecture

```
TheVault/
├── TheVaultApp.swift        App entry, menu commands, routing
├── Models/                  MediaItem, Source, Project, Tag, MediaFilter, MediaAnalysis
├── Persistence/             Versioned JSON store behind a VaultStore protocol
├── Stores/                  LibraryStore (single source of truth), AppSettings
├── Ingestion/               Metadata extraction, thumbnails, geocoding, volume monitoring,
│                            on-device analysis, Claude enrichment
├── DragDrop/                Multi-file ordered drag-out
├── Utilities/               Theme, Keychain, extensions
└── Views/                   Home, Browser (grid/timeline/map), Filter, Detail,
                             Projects, Sidebar, Settings, Common
```

**Persistence.** The index is a versioned JSON document behind a `VaultStore` protocol — a clean seam to swap in Core Data / SQLite for very large libraries. Thumbnails are cached as JPEGs keyed by path + size.

**Performance.** Thumbnails generate asynchronously for visible cells only (`LazyVGrid` / `LazyVStack`). Indexing and analysis run on background queues and stream results in batches. The filtered-item list is cached and recomputed only when its inputs change.

---

## Known limitations

- On-device analysis thresholds are heuristic and may need tuning for your footage — they're centralized in `OnDeviceAnalyzer.T`, and every decision is backed by a raw score in `AnalysisScores`.
- Wind-noise detection is not auto-flagged: reliably separating low-frequency rumble from ordinary speech needs real spectral analysis. The flag exists for the AI tier and manual use.
- Metadata extraction uses synchronous AVFoundation accessors (deprecated on macOS 13+ but functional); migrating to the async `load(_:)` API is a straightforward follow-up.
