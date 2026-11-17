# Markdown Digest verification

Verified 16 November 2026 in **0.5.4 (20)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **180 passing core tests**.

## Scope and design

Markdown Digest is an everyday tool in New Files and the File menu, independent of optional Developer Tools. Select explicit UTF-8 text files, inspect captured contents, reorder or remove files, then prepare a digest before copying or saving. A compact File/Digest switch shares the read-only editor. Both output actions use the complete prepared document and return the visible preview to Digest.

Limits are 32 files, 1 MiB per file, 8 MiB total source text and 12 MiB output. Folders, direct symbolic links, malformed UTF-8 and binary control characters are rejected. The document has numbered filename-only headings and literal code fences. Full source contents remain, so it is not a redaction tool. No folder scanning, code execution, source rendering, network calls or history are added.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **180 tests passed in 2.760 seconds.** Ten digest tests cover immutable capture, Unicode/CRLF preservation, selected order, embedded Markdown/HTML and long fences, escaped headings, duplicate basenames, invalid selection/symlinks/binary input, per-file/aggregate/output limits, empty text, bounded previews with full publication, existing-output and source collisions, cancellation and failed additions that preserve prior captures.
- The final native Debug build succeeded after the UI focus fixes. Only the existing App Intents metadata-skipped notice was reported.
- Astro reported zero errors/warnings/hints, built seven routes and passed local links/assets, canonical metadata, landmarks and pinned Air hashes.
- Independent filesystem assertions verified the live outputs' byte lengths, source contents, order, removal, preservation of the first output and absence of automatically added source paths. The saved preferences matched their pre-test snapshot.
- The site's existing Satteri Markdown parser independently parsed both live outputs: the first contained exactly three code blocks with `markdown`, `rust`, `text` language hints, the second exactly two with `rust`, `markdown`. Parsed block contents matched the fixtures (apart from the parser's closing newline convention). Heading counts were four and three. Only heading, paragraph and code nodes appeared; the nested Markdown fence stayed literal.

Logs: [core tests](markdown-digest-core.txt), [native build](markdown-digest-build.txt), [website](markdown-digest-site.txt).

## Live native verification

Reviewed the 640 × 650 pt workspace in the user's current dark appearance with shared native Glass actions, using only synthetic files under `/tmp/CloakTools-Markdown-Digest-Verification`.

1. Opened from New Files. Chose three fixtures: Markdown notes with nested Swift fences and Unicode, Rust source and a plain-text plan. The selection showed three files and 218 source bytes.
2. The initial test revealed that committing an unchanged name on focus loss could invalidate the file-picker completion. Added an old/new-value guard, rebuilt and repeated the initial selection successfully on the first attempt.
3. Preview Digest produced a 373-byte document. Inspected File mode, then saved while File was selected. The complete three-file digest was written as `File digest.md`, and the preview returned to Digest.
4. Moved the Rust source above the notes and removed the plan. The former prepared/saved state cleared, the list showed two files and 157 source bytes, and Preview Digest became the next action. The first-row Move Up action was disabled.
5. Attempted to add a four-byte binary fixture. The error explained that it was not UTF-8 text or contained binary controls. The two existing files and their order remained available for recovery.
6. Prepared again and saved a 279-byte digest as `File digest 2.md`. The first output remained intact. The new output contained Rust first, notes second and no removed plan/binary fixture.
7. Applied the same unchanged-value guard to Sample Files' format/count/size/unit observers. A fresh Sample Files window generated the default ten-record, 1,491-byte JSON preview on the first click. Closed both test windows and returned to New Files.

Native evidence: [digest preview](../../assets/screenshots/markdown-digest-preview-dark.png), [failed addition](../../assets/screenshots/markdown-digest-error-dark.png), [numbered save](../../assets/screenshots/markdown-digest-saved-dark.png).

## Website review

Updated Install, Support, Source and the shared Privacy content, retaining the existing Cloakyard layout and styling. Reviewed the digest guide in desktop Chrome and at 320 × 740. Text wrapped within the narrow viewport; document and viewport widths were both 320 px. Restored the viewport, closed the test tab and stopped the temporary development server.

Evidence: [desktop guide](../../assets/screenshots/markdown-digest-guide-desktop.jpg), [mobile guide](../../assets/screenshots/markdown-digest-guide-mobile.jpg).

## Boundaries

The current pass did not exercise the native Copy Digest button or change clipboard contents. Full-text preparation/publication is tested, but clipboard failure behavior remains a manual check. Automated cancellation covers core operations; interactive cancellation during a large capture and crash recovery were not exercised. Light appearance, exact minimum window dimensions, increased contrast, Reduce Transparency, full keyboard traversal, VoiceOver and localization need broader review. Everyday availability follows the unguarded everyday entry points; this pass did not toggle the user's saved Developer Tools preference.

No macOS defaults or preferences were changed. No public release, deployment, Developer ID signature or notarized installer was produced. Signing/provisioning, Finder lifecycle, supported filesystem coverage, macOS 27.0 runtime testing and broader release gates remain recorded in the roadmap.
