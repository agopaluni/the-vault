# The Vault — UX Analysis

**Build reviewed:** `main` @ `2e902e4` · **Date:** 2026-09-24
**Method:**
- A heuristic evaluation (Nielsen's 10, plus macOS Human Interface Guidelines conventions for pro apps).
- A walkthrough of the core job, done through the code and the screenshots in `docs/portfolio/images/`.
- A contrast check of the theme colors.

This was not a moderated usability test. Findings about "users" are expert predictions, and should be checked with 3–5 real editors.

## The core job

> *"I came back from a shoot with 500 clips across two cards. Get me from 'dumped footage' to 'selects on my Final Cut timeline, in order' as fast as possible, without me scrubbing every clip."*

Every finding is ranked by how much it slows that path:

**Create project → add sources → triage out junk → pick selects → order them → drag to NLE**

**Severity:**
- **UX-Critical**: blocks or breaks the core job.
- **Major**: significant friction or confusion.
- **Minor**: polish.

---

## What already works well

These are worth keeping as the app changes:

- **Projects-first launch.** Three clear doors on Home. Most media tools drop you into an overwhelming library.
- **Pool vs. selection is the right mental model**: sources are what you *have*, the project is what you *chose*. It matches how editors think about selects.
- **Non-destructive language is consistent**: "Discard" (not Delete), "Remove from Project", and confirmations that say "No files are deleted". This builds trust with people who are anxious about their footage.
- **Disconnected sources stay visible and greyed out, and repopulate on reconnect.** This is exactly right for card- and SSD-based workflows.
- **Cost transparency on AI.** "Enhance with AI (N)" shows the spend before you commit, and the free on-device tier comes first.
- **Thumbnail overlays** (duration, time, location, flag count) let you judge a clip without opening it.
- **Multi-select drag in pick order** is a real differentiator for an NLE hand-off, once it works in every view (see UX-01).
- **Visual design:** the dark neutral palette with a single amber accent reads as "pro video tool". It is consistent, restrained, and sits well next to FCP.

---

## Summary of findings

| ID | Severity | Area | Finding |
|---|---|---|---|
| UX-01 | **Critical** | Hand-off | The "In Project" tab, where selects live, can't multi-select or multi-drag |
| UX-02 | **Critical** | Filtering | FilterBar looks active in the project Grid view but does nothing |
| UX-03 | **Critical** | Trust | Actions that destroy curation work have no confirmation and no undo |
| UX-04 | **Major** | Navigation | Two overlapping "in project / source media" switches, depending on view mode |
| UX-05 | **Major** | Triage | No keyboard triage: no arrows, Space preview, or approve/reject keys |
| UX-06 | **Major** | Triage | Flag noise: "Too short" fires on a large share of normal phone clips |
| UX-07 | **Major** | Feedback | Long jobs can't be cancelled; AI failures are silent; progress hides |
| UX-08 | **Major** | Consistency | Controls appear and disappear with selection; batch actions differ by view |
| UX-09 | **Major** | Discoverability | Key actions hide in context menus; icon-only toolbar menus |
| UX-10 | **Major** | Settings | Two toggles do nothing; no key test or cost preview |
| UX-11 | **Major** | Accessibility | Tertiary text fails contrast; the grid is invisible to VoiceOver |
| UX-12 | **Minor** | Project mgmt | Can't rename projects; no delete/rename/sort on the project browser |
| UX-13 | **Minor** | Information | Counts disagree across the sidebar, headers and status bar |
| UX-14 | **Minor** | Visual | Double chevrons, crowded filter row, stacked amber segment controls |
| UX-15 | **Minor** | Detail panel | Offline video shows a bare crossed-out play icon; photo zoom is hidden |
| UX-16 | **Minor** | Menus | Duplicate View menu; ⌘A conflict; no ⌘N for a new project |

---

## Critical

### UX-01 · The selects tab can't do the hand-off
The **In Project** tab is where your curated selects live, in your chosen order. It's the list you'd drag into Final Cut. It is also the only media view that:
- selects one row at a time (no ⌘-click, no ⇧-click; ⌘A has no visible effect because rows don't show selection state)
- drags **a single file** (it still uses the old SwiftUI drag path)

So the view designed for "get my selects out" can't get them out. Users work around it in Source Media or Timeline, where the order is date order, not project order.

**Recommendation:**
- Use the same selection and drag behavior here as in the grid.
- On this tab, drag order should be **project order**, with a small "Drag in project order" note next to a "Drag all" affordance.
- Also consider **"Send to Final Cut"**: export an FCPXML of the project in order. For many editors that beats drag-and-drop.

### UX-02 · Filters that lie
In a project's Grid view, the whole FilterBar is visible, and chips turn amber when set. Setting them does nothing: the project views ignore the filter and sort. The status bar meanwhile reports a *filtered* count ("22 items · 1 filter") that may not match the screen.

This is worse than having no filters. The user concludes the filter *worked* and nothing matched, or stops trusting the counts.

**Recommendation:** apply the filter to In Project, Source Media, Flagged and By Content. This is also where it's most valuable, e.g. *"Speaking clips from day 2 not yet added"*. If some filter can't apply in a view, disable that chip with a tooltip. Never show an active filter that has no effect.

### UX-03 · Destructive actions with no safety net
| Action | Confirmation | Undo | What's lost |
|---|---|---|---|
| Sidebar ▸ Remove Source | None | None | All clips' tags, AI results and review state. **Also removes the folder from every project that shares it.** |
| Sidebar ▸ Delete Project | None | None | The project and its order. Orphaned sources and their analysis go too. |
| Sidebar ▸ Re-index | None | None | Wipes tags, analysis and project membership for that source |
| Delete Tag | None | None | The tag, removed from every clip |
| Discard (batch) | None | None | Clips vanish from view immediately |
| Clear Project Selection | ✅ | None | — |

The rest of the app talks a lot about non-destruction ("files are never touched"), but the *work* users put in (curation, triage, paid AI tags) is easy to lose with one misclick next to "Reveal in Finder" in a context menu.

**Recommendation:**
- Register the store's mutations with `UndoManager` so ⌘Z works for add/remove, discard, tag and delete.
- Confirm anything that affects more than one project, and say which ones: *"'CLIP – External Drive' is also used by Ladakh/Delhi Day 1. Remove it from the browser only, or everywhere?"*
- Make Re-index keep user data (it's a bug; see QA BUG-03).
- After Discard, show a short toast: "12 clips discarded · Undo · Show discarded".

---

## Major

### UX-04 · Two versions of the same switch
In a project:
- **Grid view** shows a segmented control: *In Project · Source Media · Flagged · By Content*.
- **Timeline and Map** show a different one: *In Project · All Source Media*.

They're separate state, so switching Grid → Timeline doesn't keep your place. "Source Media" and "All Source Media" name the same thing differently. Grid also has the Not Added / In Project scope *inside* Source Media, a third layer of the same idea.

In `03-detail-analysis.png`, two amber-highlighted segmented controls sit stacked (*All/Photos/Videos* above *In Project/All Source Media*), and they compete for the same visual weight.

**Recommendation:**
- Make **scope** one piece of project state (Selects / Pool / Pool – not added) that every view mode shares.
- Make **Flagged** and **By Content** filters or groupings within that scope, not peer tabs.
- Grid, Timeline and Map then become purely *how* you look at the chosen scope.

### UX-05 · No keyboard triage
Triaging 500 clips with a mouse is slow. The audience lives in FCP and Lightroom, where keyboard culling is expected:

| Expected | Current |
|---|---|
| Arrow keys move focus in the grid | ✗ |
| **Space** = Quick Look / play | ✗ (you double-click to open the side panel) |
| P / X (or F / U) = pick or reject, then advance | ✗ |
| 1–5 ratings or tag hotkeys | ✗ |
| ⌫ = remove from project | ✗ |
| J/K/L scrub in preview | ✗ (AVPlayerView supports some, but only when it has focus) |

**Recommendation:** a focus ring on the grid, arrow navigation, Space for a large preview (a `QLPreviewPanel` is cheap to add), and **P = add to project / X = discard, both auto-advancing**. That alone could cut a 500-clip pass from about 30 minutes to about 5. It is the most valuable UX investment in this report.

### UX-06 · Flag noise
In `02-project-grid.png`, **about half of the visible clips carry a flag badge**, mostly "Too short" (under 2 s). For phone footage, short grabs are normal b-roll. Once most clips are flagged, the badge stops meaning anything, and the Flagged tab becomes a second copy of the library.

The badge is also only a number ("⚠ 1"). You have to hover (tooltip) or open the clip to learn *what* is wrong.

**Recommendation:**
- Treat "Too short" as information, not a warning: show it as a subtle duration tint. Keep red for real mistakes (black frame, accidental start under 1 s).
- Make the threshold a setting, or learn it from the median clip length per source.
- Show the icon of the top flag on the badge itself: 🔇, 🌫 blurry, ✋ accidental.

### UX-07 · Feedback during long work
- **No cancel** for analysis or AI enhancement. Starting "Analyze All Shown" on 500 clips commits you, or you quit the app.
- **AI failures are silent.** With no credit balance, the progress bar runs "50/50", then nothing changes and the button still says "(50)". The user can't tell whether it worked.
- **Progress disappears early** when you index several sources at once.
- The status bar shows **one** of indexing / analyzing / enhancing at a time, so parallel work is hidden.
- There's no **ETA**, and nothing tells you *which* clip is being processed.

**Recommendation:**
- A small activity popover (like Safari downloads) that lists running jobs, each with progress, a Cancel button, and a result summary: "Enhanced 38 · Skipped 12 (credit balance too low) · View".
- Errors should say what to do next: "Add credits at console.anthropic.com → Billing."

### UX-08 · Controls that move
- Selecting any clip **hides** the project header's Analyze, Enhance with AI and ⋯ buttons. The UI shifts under the cursor, and the Enhance scope ("all in project") can't be applied to a selection.
- The **BatchActionBar** appears only in Grid, only for more than one selected clip, and only outside projects. Timeline has no batch bar, Source Media has its own toolbar, and Flagged has a third (triage) bar with different actions.
- **Add to Project** shows up in four places, each styled differently.

**Recommendation:**
- A single **selection bar** used by every view, with the same set of actions (Add to project, Remove, Tag, Approve, Discard, Analyze, Enhance). Actions that don't apply in the current view are disabled, not hidden.
- Header actions stay put. When clips are selected, they apply to the selection, and the label says so: "Analyze 12 selected".

### UX-09 · Discoverability
- Important actions live **only** in context menus: Rename source, Analyze a source, Re-index, Delete project, Remove from project.
- The toolbar's **Analyze** (wand icon) and **Sort** (arrows icon) are icon-only menus with no labels. With `showsTitle: false`, it isn't clear where the "Home" and "Add Source" buttons lead in context.
- "By Content" is empty until analysis has run, and the empty state doesn't offer a button to run it.
- The **size slider** for thumbnails floats bottom-right with two nearly identical photo icons.

**Recommendation:** put source actions behind a visible ⋯ on hover. Label the toolbar menus ("Analyze ▾", "Sort: Date ▾"). Every empty state should offer the action that fills it.

### UX-10 · Settings that don't do anything
- **"High-precision motion analysis"** and **"Enhance new imports with AI automatically"** don't do anything. The second one implies spending money.
- There's no **"Test key"** button. You find out the key is wrong or unfunded only after an Enhance run fails.
- There's no **estimated cost** before enhancing ("≈ $0.40 for 214 clips").

**Recommendation:** remove or implement the two toggles. Add a Test button that makes a 1-token call and reports ✓ Valid / ✗ Invalid / ⚠ No credit. Show a cost estimate in the Enhance confirmation.

### UX-11 · Accessibility
- **Contrast.** `textTertiary` (#6E6E78) is used for most captions, counts, sidebar numbers and metadata keys. It measures about **3.4:1 on the background and 3.1:1 on surfaces**, below the WCAG AA 4.5:1 minimum for small text. Much of it is 9–11 pt fixed-size text, which makes it worse. Raising it to about #8E8E98 gets past 4.5:1 without breaking the look.
- **VoiceOver.** Grid cells are covered by a transparent `NSView` that captures mouse events. There are no accessibility labels, so a screen-reader user can't find, select or open clips. Add `.accessibilityElement`, a label (filename, date, duration, flags) and actions (Select, Open, Add to Project) to each cell.
- **Selection** is shown only by an amber 3 px ring. That's the same amber as the flag badges and location pills, so selected and flagged clips look alike. Add a checkmark badge on selection.
- **Dynamic Type.** Fonts use fixed `.system(size:)` in many places, so macOS text-size settings have no effect.
- **Keyboard-only use** isn't possible (see UX-05).

---

## Minor

### UX-12 · Project management
- **Rename** in the project context menu does nothing. Neither a project's name nor its type can be changed after creation.
- The Home project browser has no rename, delete, duplicate, sort (recent / name) or search. With more than 10 projects it becomes a wall of cards.
- There's no "Recent project" shortcut on Home. A returning user always needs 2 clicks to resume work.

### UX-13 · Numbers that don't agree
- **All Media** says 504, but can show fewer, because project-only sources are hidden from it.
- **Untagged** counts every clip in the library, while All Media hides some.
- **Project** counts can include clips that have been removed.
- The status bar count follows the (ignored) filter in project Grid view.

People use counts to check their work ("did all 22 come across?"), so every count needs to match what's on screen.

### UX-14 · Visual polish
- **Double chevrons** on every filter chip (`⌄ Orientation ⌄`). The menu style adds one on top of the custom one.
- The **filter row** holds 12 controls. At the minimum window width (1040 pt) it scrolls horizontally with no scroll hint, so the Date and Location controls fall off-screen. Group the less-used filters (Orientation, Format, AI) under a "More ▾" chip.
- **Location pills** truncate to "New Delhi,…" or "Hyderab…". Show the city only, with the full name in a tooltip.
- **Thumbnails show time only.** In the Grid (not the Timeline), a date matters more across a multi-day shoot.
- The **Home** logo uses the SF Symbol `film.stack`, not your app icon, which is a missed branding moment.

### UX-15 · Detail panel
- If a clip's drive is disconnected, the video preview shows a large crossed-out play icon and nothing else. Say *"'CLIP – External Drive' is disconnected. Connect it to preview."*
- Photo zoom works only with a trackpad pinch. There are no zoom buttons, no double-click to zoom, and no fit/100% toggle.
- The **Content Tags** editor lists all 13 tags as equal-weight toggles, so AI-suggested and manually added tags look the same. Showing AI suggestions with a ✨ marker or a dashed outline explains *why* a tag is on, and makes corrections feel lighter.
- The panel is a fixed 360 pt wide, and can't be resized or popped out for a larger preview.

### UX-16 · Menus and shortcuts
- **Two "View" menus** in the menu bar. It's visible in every screenshot.
- **⌘A** is bound to "select all media", which probably breaks select-all inside text fields.
- There's no **⌘N** for New Project (⌘O is Add Source). Also missing: ⌘1/2/3 for Grid/Timeline/Map, and ⌘⌫ for Remove from Project.
- The **Selection** menu duplicates the toolbar buttons but not the batch actions (Tag, Add to Project, Discard).

---

## Prioritized roadmap

| # | Change | Fixes | Effort |
|---|---|---|---|
| 1 | Multi-select and multi-drag in the In Project tab (project order) | UX-01 | S |
| 2 | Apply filters and sort in project views | UX-02, UX-13 | S–M |
| 3 | Undo manager, plus confirmations that name the affected projects | UX-03 | M |
| 4 | Keyboard triage: arrows, Space preview, P/X with auto-advance | UX-05 | M |
| 5 | Activity popover with cancel, error summaries and next steps | UX-07, UX-10 | M |
| 6 | One scope model shared by all views, and one selection bar | UX-04, UX-08 | M–L |
| 7 | Retune flags ("Too short" as info), show the flag type on the badge | UX-06 | S |
| 8 | Contrast bump, VoiceOver labels, checkmark on selection | UX-11 | S–M |
| 9 | Project rename/delete/sort, a Recent project on Home | UX-12 | S |
| 10 | Polish: chevrons, filter overflow, menus, shortcuts, detail panel | UX-14–16 | S |

Items 1–2 are small, and they make the demo in your portfolio honest: drag your selects straight into Final Cut, and filter a project. Item 4 would most change how the app feels to an editor.

## Suggested validation

Run a 30-minute task-based test with 3–5 people who edit regularly. Give them the Ladakh cards and these tasks:
1. Make a project from both cards.
2. Find the 10 best talking-head clips from May 31.
3. Get them into a Final Cut timeline in story order.
4. Hide every junk clip.

Time each task, and note every hesitation. The expected pain points are tasks 2 (UX-02) and 3 (UX-01), which confirms the top of this roadmap.
