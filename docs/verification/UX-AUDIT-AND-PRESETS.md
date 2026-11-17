# UX audit and folder presets

Verified 15 November 2026 on macOS 27.2.1 (26B131), Apple silicon, Xcode 27.2 / macOS 27.2 SDK / Swift 6.4.2. Local native preview **0.4.0 (13)**. This records development verification, not public-release readiness.

## Audit scope

Reviewed the implemented settings categories, operation windows, routing/default-handler editors, template management, Finder handoff and shared publication/cancellation paths. Read the native UI and operation implementations, checked existing feature verification records, and ran the complete core regression suite. Live interaction focused on category navigation, routing test and draft cancellation, validation and destination recovery, image-dialog sizing, media cancellation, and the new preset workflow. Earlier end-to-end image, PDF, clipboard, routing and default-restoration evidence remains in the neighboring feature records; every combination was not manually replayed in this audit.

The website review covered its shared reading layout, navigation behavior, updated guide content and desktop/narrow rendering. The existing family identity, pinned Air styles and unique finite animation remain intact.

## Findings fixed before adding presets

| Finding | Result |
| --- | --- |
| Settings categories inherited the previous category's scroll position. | Switching categories starts at the top; Manage Folder Presets also resets navigation. |
| Some operation errors/progress could disappear into scrolling content. | Shared bounded feedback stays immediately above the fixed action row. Long errors scroll within that feedback area. |
| Destination paths were abbreviated ambiguously or scrolled away. | Shared destination rows remain beside actions, with middle truncation, full-path help and an accessibility value. |
| Creation, clipboard and image workflows offered limited recovery from an unavailable destination. | Change opens a folder picker without discarding captured content; fitting keeps its exact measured output. |
| Cancellation looked like an error, and repeated cancellation could obscure state. | Cancellation uses neutral feedback. Operations with outstanding work show Stopping and disable repeated cancellation. Late preparation results are discarded. |
| Empty required fields remained submittable in several editors. | Whitespace-only names disable the relevant action; rule/template editors check their required fields. Core filename validation remains authoritative. |
| PNG conversion left space for controls it did not need. | PNG opens at 448 × 360 pt; JPEG/HEIC use 448 × 432 pt. Format changes resize only while the window still matches its automatic height. |
| PDF assembly selection could move outside the list viewport. | Moving selection scrolls the selected row into view. |
| Programmatic PDF editor close could bypass preview cleanup. | Cleanup also runs in windowWillClose. |
| Copy Link could report success without checking the pasteboard write. | Feedback follows the actual write result. |
| Template errors could disappear when navigating settings. | Template-library errors have separate state; preview truncation counts characters consistently. |
| Media playback exposed unnecessary system integrations. | Now Playing updates and video-frame analysis are disabled, alongside the existing external playback restrictions. |
| Single-item Finder URLs accepted ambiguous extra URL components. | The parser rejects credentials, ports, paths, fragments and oversized intents consistently. |
| Long web guides required extensive scanning. | A collapsed On this page index links to sections, supports Escape and moves keyboard focus to the chosen heading. |

The language grid also adapts to width, and Conversions now labels its image defaults explicitly. Shared actions retain native Liquid Glass, semantic colors and existing opaque accessibility fallbacks.

## Folder presets

**New Files → Folder presets → Add Folder Preset…** selects a destination and opens a 480 × 400 pt editor. A preset saves a title, file type or imported template, filename and programming-content policy. **Save Preset saves choices only.** Use from its row or **File → New File from Preset** opens the existing New File review before creation. The review captures current preferences and template content; subsequent setting/template edits cannot alter that operation.

Global Hello World Off always wins. The per-language switch must also be on for a built-in starter. Always blank can further suppress generated code. Custom templates retain their saved bytes; JSON and PDF retain valid blank structures. Edit/Remove act on the preset, not its files. Missing templates require selecting another template; unavailable folders can be corrected in the editor or the operation review.

The library stores at most 32 validated, uniquely identified presets in a bounded, atomically written local JSON file. A failed validation/write does not replace the prior library. These are explicit starting points: no folder matching, folder watching, bookmark tracking, automatic creation or additional access grant is introduced.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **112 core tests passed** in 1.101 seconds. The previous 105 tests remain; two audit regressions cover destination recovery and ambiguous Finder intents, and five preset tests cover precedence, immutable custom content, structured blank documents, bounded persistence/validation and missing folders. [Core log](ux-presets-core.txt).
- Destination recovery tests include a deleted source, a rejected destination followed by a valid destination, exact measured image bytes, collision handling and absence of output at the original location.
- Preset tests cover all eight master/language/policy combinations, UTF-8/CRLF content, missing templates, malformed/duplicate/oversized libraries, unchanged storage after rejected writes, and numbered output collisions.
- Native Debug arm64 build: **BUILD SUCCEEDED**, no Swift warnings. Expected unused AppIntents metadata warnings and ad-hoc signing notes remain. Bundle **0.4.0 / 13**; Finder registration reports **0.4.0**. [Build summary](ux-presets-build.txt).
- Website: **7 routes**, zero errors/warnings/hints; local links/assets, canonical metadata, landmarks and pinned Air hashes pass. [Site log](ux-presets-site.txt).

## Live native observations

1. Switching from a scrolled Conversions category to New Files returned to the top. The link tester handled Return and Escape; destination editing could be cancelled without saving.
2. A whitespace-only filename disabled Create. Submitting `bad/name` displayed validation beside the actions and created nothing. Change selected another folder; Create produced the expected zero-byte `Destination proof.txt` there.
3. PNG conversion opened compactly. Switching to JPEG expanded the automatic height and kept quality, background, destination and actions visible. The review was cancelled without output.
4. Started a synthetic 12-second media export and immediately pressed Escape. Neutral Cancelled feedback appeared; a second Escape closed the operation. No new export was published.
5. Saved a Rust scratchpad preset targeting a synthetic directory with filename `main`. Saving wrote the preset library but **did not create main.rs**. Use opened the expected type/name/destination review. With global Hello World Off, creation produced **main.rs, 0 bytes**.
6. Relaunched in DEBUG light appearance. The preset persisted, its 480 × 400 pt editor remained readable, and Escape discarded an unsaved title change. The stored preset hash was unchanged.
7. Invoked the preset through the File menu. The second confirmed creation produced **main 2.rs, 0 bytes**, preserving the first file.
8. Removed only the synthetic preset library after checking its exact known hash and confirming that no library existed before the test. Relaunched normally; normal appearance, global Hello World Off and the original language selections remain. Web/email defaults were not changed during this audit. [Output evidence](ux-presets-output.txt).

Screenshots: [preset dark](../../assets/screenshots/folder-preset-dark.png), [preset light](../../assets/screenshots/folder-preset-light.png), [creation review](../../assets/screenshots/folder-preset-review.png), [filename feedback](../../assets/screenshots/ux-filename-feedback.png), [neutral cancellation](../../assets/screenshots/ux-media-cancel.png), [adaptive image conversion](../../assets/screenshots/ux-image-conversion.png). Filename/cancellation captures document feedback before the final destination-row pinning change; the image and preset captures show the final layouts.

## Live website observations

The Install index contains 17 sections. Selecting Folder presets updated the fragment and focused that heading. Desktop review used the normal 1728 px viewport. Install and Support both had `scrollWidth === innerWidth` at 320 px; the support index wrapped into one column, and its preset link focused the corresponding heading. Earlier in the audit, Escape and the mobile Menu → Download focus/close flow also passed. Support topics keep preset help beside template help, with Report a problem last.

Screenshots: [desktop index](../../assets/screenshots/ux-guide-index.jpg), [preset guide](../../assets/screenshots/folder-presets-guide.jpg), [mobile support](../../assets/screenshots/ux-support-mobile.jpg). The viewport override was reset, test tabs closed and local development server stopped. Nothing was published.

## Remaining verification and release boundaries

- The audit covers source review, automated regressions and the live flows above. Spoken VoiceOver, the complete Reduce Transparency/increased-contrast matrix, all minimum-window states and long-label/localization stress remain unverified. It is not an exhaustive accessibility or security certification.
- Presets store ordinary paths, not security-scoped bookmarks; renamed folders are not followed. Permissions and Finder scope restrictions still apply. There is no related-file-set or folder-template creation yet.
- Broader large-file, cloud-provider, disk-full, abrupt-termination and adversarial cancellation/publication coverage remains open as recorded in the earlier feature notes.
- Developer ID signing, notarization, installer/update lifecycle, App Group Finder scopes and real Edge/profile routing remain release gates. This is an ad-hoc local preview.
