# The Vault — Portfolio Page Brief

Everything needed to build the project page: the copy (written to drop straight in), the page structure, and the shot list for images.

Written to match the structure and voice of the PoliFrame page: category tag, title, one-line hook, credits block, numbered steps with conversational headers, then a closing reflection.

---

---

# PART 1 — THE COPY

Paste-ready. Section labels in `SMALL CAPS` match the PoliFrame page's `STEP 1 / FINAL RESULT` treatment.

---

### `SOFTWARE / MACOS` · `2026`

# The Vault

**Building a macOS app that watches my footage so I do not have to.**

[View the source on GitHub →](https://github.com/agopaluni/the-vault)

---

### CREDITS

| | |
|---|---|
| **TYPE** | Personal project |
| **ROLE** | Design, engineering |
| **TOOLS** | Swift, SwiftUI, AppKit, Vision, AVFoundation, Accelerate, Claude API |
| **YEAR** | 2026 |

---

I shoot on an iPhone and a Sony camera at the same time, which means every trip ends the same way. Two card readers, a folder called `PRIVATE/M4ROOT/CLIP` full of files named `C1398.MP4`, another folder of `IMG_2503.MOV`, and no way to tell any of them apart without opening every single one. After a trip to Ladakh I had a little over five hundred clips sitting on two drives and no interest in scrubbing through all of them to find the ten I actually wanted.

So I built the tool I wanted. It is a native macOS app that indexes footage across every card and drive, runs each clip through an analysis pass that flags the junk and tags the content, and then lets me pull the good takes straight into Final Cut. Here is the journey.

---

## STEP 1

### What's the problem?

The problem is not storage. Storage is solved. The problem is that a camera gives you five hundred files with sequential names and no memory of which ones were any good.

What I actually do after a shoot breaks into three jobs, and the tools I had were bad at all three:

**Finding footage across sources.** My clips live on an SD card, an external SSD, and my internal drive at the same time. Finder can show me one folder at a time. It cannot show me "everything I shot on this trip, from every card, sorted by time."

**Throwing away the garbage.** A meaningful chunk of any shoot is unusable. Clips where I hit record by accident and stopped a second later. Clips with the lens cap on. Shots so shaky or so badly exposed that there is no saving them. Every one of those still has to be opened and watched before I know to delete it.

**Remembering what is in the good stuff.** Two weeks later I cannot tell you which file is the interview and which is the mountain. That information only exists inside the video, so finding it means watching it again.

None of that is creative work. It is filing. I wanted the computer to do the filing.

---

## STEP 2

### Before building anything, I looked at what already existed

I use these tools already, which is how I knew where they stop.

**Final Cut Pro libraries** do keywording well, but only once footage is already imported into a library. That is the step I was trying to survive. It also wants to own your media, which is the opposite of what I wanted.

**Lightroom** is excellent at exactly this for photos, and that was the model I kept coming back to. Its weakness is video. It will hold a clip, but it will not tell me anything about what is inside it.

**Finder and Bridge** are file browsers. They show me names and dates. They cannot tell me a clip is out of focus.

The gap was specific: nothing would look at the footage itself, tell me what was wrong with it, and let the original files stay exactly where they were. That last part mattered to me more than anything. Every tool in this category wants to import, copy, or reorganize your media. I wanted a tool that only ever reads.

So the first rule I wrote down, before any code, was that the app is never allowed to move, modify, or delete an original file. Everything it knows lives in its own index. If the app disappeared tomorrow my footage would be untouched.

---

## STEP 3

### Designing the thing around how a shoot actually works

My first version was wrong, and it was wrong in an interesting way.

I built it as a media browser first. You add source folders, you get one big library, and projects were a thing you tagged clips into afterward. It worked, and it felt backwards immediately. I do not think in terms of a library. I think in terms of *the Ladakh trip*. The project is the unit, not the collection.

So I rebuilt the navigation. The app opens on a project screen, not a browser. You create a project, attach the cards and drives it came from, and work inside it.

The second thing I got wrong was subtler. When you attached a source to a project, every clip on that card became part of the project automatically. That sounds convenient and it is actually useless, because a project containing all five hundred clips is just the card again with extra steps.

The fix was to split the two ideas apart:

- **Sources are a pool.** Everything available to the project.
- **The project is a selection.** Only what you deliberately put in it.

That one distinction is what makes the app worth using. You browse the pool, filter it down to talking-head shots from one afternoon that are not flagged as unusable, select those, and add them. The project becomes the edit-worthy cut, and the pool stays there when you need more.

I also made it so a folder is only ever indexed once, no matter how many projects use it. I did not do this for elegance. I did it because I had already shipped the version that indexed a folder twice, and I was looking at a library that claimed to have 1,008 clips when I knew I had shot 504.

---

## STEP 4

### Making the computer watch the footage

This was the part I actually wanted to build, and the part where I made the most deliberate engineering decision.

The obvious approach in 2026 is to throw every clip at a vision model and let it tell me what is there. I did not want to do that, for two reasons. It costs money for every single clip, including the ones with the lens cap on. And it needs a network and an API key to do anything at all, which is a bad property for a tool you use on a plane.

So I split the analysis into two tiers.

**Tier one runs on my Mac and is free.** For each clip it samples a handful of frames and a window of audio, then measures:

| Signal | How |
|---|---|
| Black frames, lens cap | Mean luminance and variance across sampled frames |
| Blur | Variance of a Laplacian convolution, the standard focus measure |
| Shake and motion | Frame-to-frame difference, and the variability of that difference |
| Exposure | Luminance histogram, clipped highlights and shadows |
| Talking head | Face detection through Apple's Vision framework |
| Audio problems | Peak and RMS through Accelerate, for clipping and silence |
| Too short | Duration, which I already had from the metadata pass |

None of that needs a model or a network. It catches the unusable footage, which is the bulk of what I wanted thrown out, and it costs nothing.

**Tier two is Claude, and it only runs when I ask.** It sends one to three downsampled keyframes per clip and gets back richer content tags and a one-line description of the shot. It is deliberately gated: it skips anything tier one already flagged as a mistake, it skips clips it has already analyzed, and it caches results against a fingerprint of the file so a clip is never paid for twice. The cost lands around one to two dollars per thousand clips, and nothing is spent until I press the button.

The design principle underneath all of it: **the AI gives suggestions, never decisions.** Every tag it produces can be overridden by hand. "Discard" hides a clip from view and never touches the file. I wanted to be able to disagree with the tool without losing anything.

---

## STEP 5

### The parts that fought back

The honest version of this project is that the interesting problems were not the ones I planned for.

**Dragging more than one clip out of the app.** The entire point is pulling selected takes into Final Cut, and I could only ever drag one. SwiftUI's drag API hands over exactly one file, which I knew going in, so I dropped to AppKit and built a real drag session. It still dropped files. I would select twenty-two clips and seven would land.

I stopped guessing and made the app write down what it was handing over. The log said twenty-two unique, valid, existing files. So the problem was not what we were sending, it was what happened after. The cause turned out to be that I was starting the drag from the thumbnail's own view, and SwiftUI recycles those views constantly while you scroll, so the thing that owned the drag got destroyed halfway through. Moving the drag to an object that outlives the cell fixed it.

That fix is three lines. Finding it took four wrong theories, and it only got solved once I made the app show me its own evidence instead of theorizing about it.

**Scrolling that fought back.** The grid jumped and refused to reach the bottom row. It was not a layout bug. The filtered list of clips was being recalculated from scratch on every render, and the timeline view was asking for it once per thumbnail, so a five-hundred-clip view did five hundred full filter-and-sort passes per frame. Caching the result made it smooth.

**Wind noise that was never there.** My first audio analysis flagged wind on almost everything. My method compared the signal to a high-passed version of itself to guess how much low-frequency energy it had, which sounds reasonable until you notice that at the sample rate I was using, ordinary speech is *also* mostly low frequency. The detector was not broken; the idea behind it was.

I turned it off. Detecting wind properly needs real spectral analysis, and shipping a flag that fires on every clip is worse than shipping no flag at all. A false positive costs the user trust, and this one was costing it constantly.

---

## FINAL RESULT

The app is about 7,200 lines of Swift across 48 files, and I use it on my own footage.

A shoot now goes: create a project, point it at both cards, press Analyze, and come back to a library where the accidental one-second clips and the lens-cap shots are already flagged. Filter to what I want, select it, drag it into Final Cut in the order I picked it.

It is open source, and it works on someone else's machine with their own API key. I verified that by cloning it fresh and building it as a stranger would.

---

### What I took from it

The thing I keep thinking about is that the best engineering decision in this project was choosing to do most of the work without AI. It would have been faster to send everything to a model. It would also have been slower to run, cost money per clip, and stopped working offline. Figuring out which problems actually needed a language model, and which ones were just signal processing I could do locally, is the decision I am proudest of.

The other lesson was cheaper to learn and harder to accept: when something is broken and you have a theory, the theory is usually wrong. I lost an afternoon to the drag bug guessing at causes. I solved it in ten minutes once I made the program tell me what it was actually doing.

---

---

# PART 2 — PAGE STRUCTURE

How to lay this out, matching the PoliFrame page.

### Section order

1. **Hero** — category tag, year, title, one-line hook, GitHub link
2. **Credits block** — type / role / tools / year
3. **Intro paragraph** — the Ladakh setup, ending on "Here is the journey."
4. **Step 1** — the problem, with the three-jobs breakdown
5. **Step 2** — prior art, ending on the non-destructive rule
6. **Step 3** — the pool/selection model (your main design decision)
7. **Step 4** — the two-tier analysis (your main technical decision)
8. **Step 5** — debugging stories
9. **Final result** + closing reflection
10. **Prev/next project nav**

### Design notes

**Lead with a screenshot, not a logo.** The app is dark and dense, and a grid of thumbnails with amber flag badges reads instantly as "media tool." Put the browser or project view directly under the hero.

**The app's palette is already your accent palette.** Near-black background (`#1A1A1E`), amber accent (`#FFB020`). If the page sits on a light background, frame the screenshots in a dark container so they do not float.

**Steps 3 and 4 carry the weight.** Those are the design decision and the engineering decision. Give each one a full-width image. Everything else can be text.

**Step 5 wants no images.** It is a story about being wrong. A wall of text is fine there, and the contrast against the image-heavy sections makes it read as a change of pace.

**Use the tables.** The tier-one signals table and the credits block both break up long text, and they signal technical depth faster than a paragraph would.

**Pull quote candidate:** *"The AI gives suggestions, never decisions."* That line is the thesis of the project and works as a large-type break between Step 4 and Step 5.

---

---

# PART 3 — IMAGES

Captured from the running app, cropped to remove the menu bar, sized to 2400px wide. All in `images/`.

| File | What it shows | Use it in |
|---|---|---|
| `01-home.png` | Home screen, three-option launcher | Hero, or Step 3 |
| `02-project-grid.png` | Grid of clips with flag badges, durations, location pills | Hero — best "what is this" shot |
| `03-detail-analysis.png` | **The key image.** Grid + detail panel: Analysis flags, Content Tags by category, full metadata | Step 4 |
| `04-timeline.png` | Timeline grouped by capture day with date headers | Step 3 |
| `05-map.png` | Map view, GPS pins across India | Step 1 |
| `06-new-project.png` | New Project sheet with project-type picker open | Step 3 |
| `07-project-list.png` | Ordered project list view | Step 3 |

### Notes on specific images

**`03-detail-analysis.png` is the one to lead Step 4 with.** It shows the whole thesis in one frame: a clip flagged "Too short," content tags grouped into Subject / Motion / Audio with B-Roll and Speaking checked, and the metadata panel with coordinates, camera, codec, and frame rate. If the page only gets one large image, use this one.

**The sources in that shot read "Disconnected" and greyed out.** That is not a bug to hide, it is the hot-plug behavior working: the cards were unplugged, the clips are still browsable, and the thumbnails still render from the disk cache. Worth a caption saying exactly that, because it demonstrates a design decision rather than an accident.

**`02-project-grid.png` works best as the hero.** Dense thumbnails, amber flag badges, timestamps and location pills all visible at a glance. It reads as "media tool" instantly, which a screenshot of the Home screen does not.

### Still worth capturing

Two shots I could not get without driving the UI, both easy to grab yourself:

- **Source Media tab with clips selected** and the "Add to Project (N)" bar showing. This is the pool-versus-selection idea made visible, and it belongs in Step 3.
- **A short screen recording of the drag-out** — select several clips, drag into Final Cut, watch them land in order. That is the single most convincing thing the app does and it cannot be shown in a still. Five seconds, trimmed, looped. Worth more than any other image on the page.

---

## Facts to keep accurate

Pulled from the codebase, so the page does not overstate:

- 48 Swift files, ~7,200 lines
- macOS 13+, SwiftUI + AppKit
- Frameworks: Vision, AVFoundation, AVKit, Accelerate, ImageIO, MapKit, CoreLocation, Security (Keychain), CryptoKit, Combine
- Model: `claude-haiku-4-5`, called over `URLSession` with structured outputs
- Real library tested against: 504 clips across an SD card and an internal drive
- The deduplication fix: 1,008 indexed records collapsed to 504 actual files
- Four schema versions, with migrations that preserve tags, analysis, and curation state
- API cost: roughly $1–2 per 1,000 analyzed clips
- API key stored in the macOS Keychain, never on disk in the repo

**Do not claim:** a user base, production deployment, or test coverage. There is no test suite. If a page section invites that question, the honest framing is that it is a personal tool that solves a real problem for one person, which is exactly what it is.
