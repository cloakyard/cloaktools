# UX consolidation verification

Verified 16 November 2026 in **0.5.9 (25)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. This implements the navigation follow-up from the [macOS feature audit](../MACOS-FEATURE-AUDIT.md), with no new utility or core-processing changes.

## What changed

- General's nine quick actions become three: New File, New File Set and Make It Fit.
- New Files starts with New File and a collapsed built-in catalog. Saved templates precede file sets and folder presets. Live review caught empty workflow sections displacing an existing favorite; the final layout restores the favorite near the top.
- Markdown Digest stays visible under Text & sharing. More text tools expands QR Code, Text Cleanup and Clipboard to File, with a subtitle that names its contents.
- Conversions leads with Make It Fit and Export Media, followed by export recipes. Image & PDF tools, Image conversion defaults and Supported files & limits expand separately.
- File uses Text & Sharing and Images & PDFs submenus; all operation actions and existing keyboard bindings remain. Developer Tools keeps its existing availability condition.
- Native grouped surfaces, disclosure controls and shorter helper text reduce the initial catalog. Operation windows retain their existing Liquid Glass actions.
- The website shows the final Conversions layout and updates Install, Support and Source to the current navigation. README, design, architecture and roadmap describe the same behavior.

## Native verification

`./scripts/build-native.sh` passed for the final Debug app and embedded extension. An initial Section initializer error was fixed before the successful builds. No core source, schema, preference model or output handler changed. The earlier **216 passing core tests** belong to [0.5.8](QR-READING.md); they were not rerun for this presentation-only update. No tests that merely duplicate UI structure were added.

The live check used the normal 900 × 650 pt settings window in dark appearance:

1. The complete collapsed Conversions overview, including footer, fits the window. Expanding Image & PDF tools reveals all three launchers. Image conversion defaults reveals the existing PNG format, beside-original location and reveal setting; none was changed.
2. New Files places the existing favorite Project Note above file sets and presets. Expanding Built-in file types reveals Plain Text, Markdown, JSON and PDF with the existing Developer Tools choice On. Collapsing it restores the compact overview.
3. More text tools expands all three launchers with readable subtitles and accessible Open labels. QR Code opens Create from that row; Escape returns to the same expanded group and scroll position. Switching categories recreates the collapsed overview.
4. General exposes exactly three quick actions. Its Make It Fit action opens the expected image picker; cancelling returns normally.
5. The File menu exposes the grouped text/image/PDF actions and conditional Developer Tools menu. Read QR Code under Text & Sharing opens directly in Read mode. Escape returns to settings.
6. **⇧⌘K** opens Convert an image before its submenu has been opened. **⇧⌘P** opens the PDFs/images picker. Both were cancelled without selecting or writing output.
7. New Files was restored as the selected category, at the top with both groups collapsed. Before/after JSON comparisons confirm existing preferences, default-handler records, routing rules, templates and file sets are unchanged. No clipboard reads/writes, system default changes, source-file exports or saved-library mutations were performed in this pass.

Evidence: [native build](consolidation-build.txt), [stored-state comparison](consolidation-preferences.txt), [Conversions](../../assets/screenshots/consolidation-conversions-dark.png), [New Files](../../assets/screenshots/consolidation-new-files-dark.png), [expanded text tools](../../assets/screenshots/consolidation-text-tools-dark.png).

## Website verification

`npm --prefix apps/site run verify` passed after the final content edit: zero Astro errors, warnings or hints, all seven routes, local links/assets, canonical metadata, landmarks and pinned Air hashes. The homepage now uses the final native Conversions capture; Install and Support explain where each moved tool lives, and Source distinguishes current UI checks from the historical core-test count.

Chrome review covered the product section and Install guide at 1728 × 1117, then the product section, guide and moved-tool help at 320 × 740. Text and groups wrap without overlap; measured document width equals viewport width on the checked desktop product page and mobile product, guide and support pages. No browser warnings/errors were recorded. The temporary viewport was reset, the test tab closed and the owned development server stopped.

Evidence: [website verification](consolidation-site.txt), [desktop product](../../assets/screenshots/consolidation-site-desktop.jpg), [desktop guide](../../assets/screenshots/consolidation-guide-desktop.jpg), [mobile product](../../assets/screenshots/consolidation-site-mobile.jpg), [mobile guide](../../assets/screenshots/consolidation-guide-mobile.jpg), [mobile moved-tool help](../../assets/screenshots/consolidation-support-mobile.jpg).

## Limits and next work

This pass does not certify spoken VoiceOver, minimum-size resizing, light appearance, increased contrast, reduced transparency, long translations or the complete keyboard focus order. Developer Tools was already On and was left unchanged; fresh-install Off behavior remains covered by earlier tool-selection verification, not a fresh runtime check here. No populated export-recipe or folder-preset library was available for this live pass; those existing rendering/actions were retained.

Signing/notarization, configurable Finder scopes, verified Edge profiles and the remaining accessibility/release matrix remain open. No new OCR, renaming, archive, Keep Awake or generic inspector is queued. Further feature work must establish a specific benefit beyond the native macOS workflow.
