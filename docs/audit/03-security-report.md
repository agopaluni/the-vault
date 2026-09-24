# The Vault — Security & Privacy Evaluation

**Build reviewed:** `main` @ `2e902e4` · **Date:** 2026-09-24
**Scope:** the macOS app source, entitlements and build settings, the build script, the public git history, and on-disk data (`~/Library/Application Support/The Vault`, `~/Library/Caches/The Vault`).
**Method:** manual code review and configuration review, with spot checks against the live install. No dynamic testing or fuzzing.

## Threat model

The Vault is a single-user, local desktop app with one outbound integration.

| Asset | Where it lives |
|---|---|
| Anthropic API key (costs money if stolen) | macOS Keychain |
| The user's footage (private and often personal) | Read in place on local and removable volumes |
| Index: file paths, GPS for 98 of 504 clips, security-scoped bookmarks, tags | `VaultIndex.json` (plaintext) |
| Frames sent to Anthropic, coordinates sent to Apple | In transit, over HTTPS |

**Realistic attackers:**
1. A **malicious or corrupted media file** on an SD card or drive. This is the main untrusted input: the app parses every file it indexes.
2. **Other software running as the same user**, reading the index or key.
3. **Prompt content inside footage**: text visible in frames that are sent to Claude.
4. **Accidental disclosure**: the public GitHub repo, or backups.

**Out of scope:** network attackers beyond standard TLS, and physical access to an unlocked machine.

## Summary

| ID | Rating | Title |
|---|---|---|
| SEC-01 | **Medium** | A crafted media file crashes the app on every mount (DoS) |
| SEC-02 | **Medium** | Untrusted media is parsed in an unsandboxed process |
| SEC-03 | **Low** | Keychain item settings and prompt fatigue from ad-hoc signing |
| SEC-04 | **Low** (privacy) | Frames go to Anthropic without an in-app disclosure or confirmation |
| SEC-05 | **Low** (privacy) | GPS coordinates go to Apple's geocoder automatically, with no setting |
| SEC-06 | **Low** | The index is stored in plaintext, with no integrity protection or backup |
| SEC-07 | **Low** | Dormant file-promise code deletes existing files at the drop target |
| SEC-08 | **Info** | Prompt injection through on-screen text: already well contained |
| SEC-09 | **Info** | Build script strips quarantine; ad-hoc identity; placeholder bundle ID |

**Nothing Critical or High was found.** The app has no server, opens no listening socket, uses no web view, spawns no shell, and has no third-party dependencies. That removes most of the usual attack surface.

## Verified good practices

- **The API key is never written to disk outside the Keychain.** I checked `VaultIndex.json`, the app's UserDefaults domain, and the **entire git history** (`git log --all -p`): none of them contain an `sk-ant-` string.
- The key is entered in a `SecureField`, trimmed, and read from the Keychain only when needed for a call. It is never logged. The three `NSLog` calls log paths and counts, not secrets.
- API traffic goes to a hard-coded `https://api.anthropic.com` endpoint over TLS, using system trust.
- **Model output is strongly constrained.** Structured outputs use an `enum`-restricted tag list, and unknown tags are dropped by `ContentTag(rawValue:)`. The free-text `sceneDescription` is shown with `Text(String)`, which renders verbatim: no Markdown and no links.
- **The hardened runtime is enabled** (`ENABLE_HARDENED_RUNTIME = YES`), and no exception entitlements are granted (no JIT, no unsigned-memory, no disable-library-validation).
- **Originals are never written to.** Every file API on source media is read-only. Drag-out uses `.copy` operations only.
- `.gitignore` excludes build output, `.DS_Store` and the unrelated `morvital-site/` folder.
- `~/Library/Application Support` is `drwx------`, so other *local users* can't read the index.

---

## SEC-01 · A crafted media file crashes the app (Medium)

**CWE-190 / CWE-248: integer conversion trap, leading to denial of service**

`MetadataExtractor.fourCCString` converts each byte of a video track's codec FourCC with `CChar(UInt32)`. Any byte ≥ 0x80 **traps and kills the process**. I confirmed this with a standalone Swift test (*"Fatal error: Not enough bits to represent the passed value"*).

A file's format subtype is controlled by whoever made the file. A small crafted `.mov` on an SD card or shared drive will:
- crash the app as soon as the folder is indexed
- never be marked as indexed, so the crash comes back **every time that volume is mounted** while the app is running (the reconnect handler re-scans)

Nearby conversions that also trap on hostile values:
- `Int(abs(size.width))` on NaN or infinity (`MetadataExtractor.swift:119`)
- `Int(duration.rounded())` on an infinite duration (`MediaItem.formattedDuration`)
- an unclamped `MKCoordinateRegion` from out-of-range GPS strings (`MapBrowserView.fitRegion`), which makes MapKit throw

**Fix:**
- Use `truncatingIfNeeded:` for the byte conversions.
- Check `isFinite` before any `Int(...)` of a Double that comes from a file.
- Validate latitude and longitude ranges at extraction.
- Add a malformed-file test folder to CI (see the QA report, *Test gaps*).

## SEC-02 · Untrusted media is parsed in an unsandboxed process (Medium)

**CWE-250: execution with unnecessary privileges**

`com.apple.security.app-sandbox` is `false`. Every indexed file goes through ImageIO, AVFoundation (including `AVAssetReader` audio decode) and Vision, inside the app's own process.

These system frameworks have had memory-corruption bugs exploited through crafted images and videos: the ImageIO and CoreMedia CVEs in recent years, several of which were zero-click. If a crafted file on a card hits one of these bugs in The Vault, the code runs with **the user's full privileges**. That means home-folder access, whatever TCC grants the app already holds, and possibly Full Disk Access, which the README suggests granting.

This risk comes from macOS itself, not from this code; Finder and Photos parse the same files. But the design raises the stakes:
- The app **deliberately walks whole removable volumes**, the classic delivery route for malicious media.
- The README asks users to grant **Full Disk Access** as a troubleshooting step.
- `files.user-selected.read-only` and `files.bookmarks.app-scope` are declared but **have no effect** without the sandbox, which can give readers a false sense of containment.

**Options, from most to least containment:**
1. **Turn on the App Sandbox.** The code already records security-scoped bookmarks per source. The work is resolving them with `startAccessingSecurityScopedResource()` before *every* read, including thumbnails, analysis, playback and drag. Today that only happens in `IngestionService`.
2. **Move parsing into a sandboxed XPC service** (metadata, thumbnails, analysis) that has read-only access to the chosen folders. The main app stays unsandboxed for drag-and-drop convenience. A crash in the service also stops taking the UI down with it, which fixes SEC-01's impact as a side effect.
3. At minimum, **remove the Full Disk Access advice** from the README. Point users to Files and Folders or Removable Volumes permissions instead.

## SEC-03 · Keychain item settings and prompt fatigue (Low)

**File:** `TheVault/Utilities/KeychainStore.swift`

- **Item settings.** The item is created with `kSecAttrAccessibleAfterFirstUnlock` rather than `…AfterFirstUnlockThisDeviceOnly`. `kSecUseDataProtectionKeychain` is not set, so it lives in the legacy login keychain. There, access is governed by an ACL tied to the app's code signature.
- **Prompt fatigue (the main issue).** The app is ad-hoc signed, so every rebuild has a new signature. The ACL no longer matches, and **macOS asks for the login password at every launch** after a rebuild. That happens because `AppSettings.init` reads the key eagerly (you've already seen this). Training users to type their password into Keychain prompts on sight is poor security hygiene. It also makes "Always Allow" the path of least resistance.
- **Service name.** `com.thevault.apikey` is generic. Another app can't read it without triggering a prompt, but a prompt naming a plausible service is easy to approve by mistake.

**Fix:**
- Store only a `hasClaudeKey` boolean in UserDefaults. Touch the Keychain only when saving, removing or starting an Enhance run.
- Use `…ThisDeviceOnly`.
- Namespace the service under a domain you control, e.g. `com.atharvgopaluni.thevault.anthropic`.
- If you ever sign with a Developer ID, add `kSecUseDataProtectionKeychain` together with a keychain access group.

## SEC-04 · Frames go to Anthropic without an in-app disclosure (Low, privacy)

The README says clearly that Enhance with AI uploads 1–3 frames per clip. **Inside the app, the only signal is the button label** "Enhance with AI (N)". There is no first-run consent, no statement of what data leaves the machine, and no confirmation before spending credits on a large batch.

Footage often includes other people, homes, documents and screens. People filmed in it didn't agree to it being sent to a third-party API.

**Fix:** show a confirmation on the first run (and optionally every run) along these lines: *"Send 3 low-resolution frames from each of 214 clips to Anthropic for tagging. Estimated cost ≈ $X. Frames aren't stored by The Vault beyond the resulting tags."* Include a "don't ask again" option, and link to Anthropic's data-retention policy.

## SEC-05 · GPS coordinates go to Apple automatically (Low, privacy)

`IngestionService.scheduleGeocoding` sends the coordinates of **every geotagged clip** to Apple through `CLGeocoder` as soon as it's indexed. That was 98 clips in your library. There is no setting to turn it off. The README says the core features work with no network, but doesn't mention that the app *uses* the network when it's available.

The data volume is small and it goes to a system service, so the risk is low. It is still location history leaving the machine without the user choosing it.

**Fix:** add a Settings toggle, "Look up place names for GPS-tagged media (sends coordinates to Apple)". Mention it in the README's privacy notes.

## SEC-06 · Plaintext index with no integrity protection (Low)

`VaultIndex.json` (731 KB) is plaintext. It holds every indexed file path, GPS coordinates, security-scoped bookmark blobs, and all curation data. Any process running as the user can read it. Because the app is unsandboxed, it doesn't get the "App Data" container protection that recent macOS versions give sandboxed apps. The file is also copied into Time Machine and any cloud backup of `~/Library`.

The more serious effect is on integrity. A malformed or tampered index makes the app fall back to an empty state and then overwrite the file (QA **BUG-02**). That lets anything that can write one byte to the file destroy the user's work.

**Fix:**
- Handle load failures safely (see BUG-02).
- Keep a rolling backup.
- Optionally exclude the thumbnails cache from backups. That's a privacy win too, since the cache holds 28 MB of decoded frames from private footage.
- Encryption at rest isn't needed for this threat model.

## SEC-07 · Dormant file-promise code deletes existing files (Low)

`MediaDrag.swift:84-86`: `PromiseDelegate` runs `removeItem(at: url)` on the destination before copying. Nothing uses `MediaFilePromiseProvider` today. If it's ever wired up, dropping onto a folder that already holds a file with the same name will **silently delete the user's existing file**.

**Fix:** delete the dead code, or write to a unique name (`name 2.mov`), matching Finder.

## SEC-08 · Prompt injection through on-screen text (Info)

Frames can contain text, such as signs or a laptop screen reading "ignore previous instructions…". Nothing here gives that text anywhere dangerous to go:
- The response is JSON restricted by the schema, and tags are checked against an enum.
- The model has no tools, and its output never reaches a shell, a file path, a URL or a web view.
- The worst case is wrong tags or a misleading `sceneDescription`, which the user can see and override.

`max_tokens: 300` caps both cost and output length. No action is needed. Keep this in mind if the AI tier later gets tools or writes file names.

## SEC-09 · Build and distribution notes (Info)

- `build_and_install.sh` runs `xattr -dr com.apple.quarantine` on the installed app. That's fine for something you built yourself. Don't reuse it on downloaded binaries, and don't recommend it to others as a Gatekeeper workaround.
- `rm -rf "${INSTALL_DIR:?}/$APP_NAME"` is correctly guarded against an empty variable.
- Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) means other people's binaries can't be verified. The README correctly says there is no release build. If you ever ship one, use Developer ID signing plus notarization.
- The bundle ID `com.thevault.TheVault` uses a domain you don't own. Switch to reverse-DNS under your own domain before any distribution. It also namespaces the Keychain and UserDefaults.
- The repo has no dependencies, lockfiles or CI secrets, so supply-chain exposure is minimal.

---

## Recommended order

1. **SEC-01** (a few lines, and it also closes a QA S1).
2. **SEC-06 / BUG-02** safe load handling (protects all user data).
3. **SEC-03** lazy Keychain read (also fixes the launch prompt).
4. **SEC-04 + SEC-05** consent and settings (small UI work, big trust gain).
5. **SEC-07** delete the dead code.
6. **SEC-02** sandbox or XPC (the biggest effort; do it before handing builds to anyone else).
