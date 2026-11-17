# Text Cleanup verification

Verified 16 November 2026 in **0.5.5 (21)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **189 passing core tests**. The preceding [UX/UI audit](UX-AUDIT-TEXT-CLEANUP.md) records shared design fixes.

## Behavior

Text Cleanup is available in everyday mode through New Files → Text Cleanup and File → Text Cleanup. Input is typed/pasted explicitly, or populated with a fixed Try Example sample. A compact card offers line-start/end trimming, space/tab collapsing and Keep all / Keep one / Remove empty-line policies. Only trimming line ends starts enabled.

Preview Changes preserves the editable input and prepares separate output. Input/Result share the native editor with matching accessibility labels. Changing input/options clears the result; renaming only changes the save name. Copy/Save always uses complete prepared output, even while Input is visible, and returns to Result. Save uses ordinary `.txt` output with safe numbered collisions. Empty output can be saved, with Copy disabled.

Only ASCII spaces and tabs are transformed. A blank line contains only those characters. Keep one retains the first in a consecutive run. CRLF, CR and LF sequences on retained lines, Unicode text, BOMs, nonbreaking spaces and other Unicode separators stay unchanged. Cleanup can change code indentation or Markdown trailing-space semantics; compare before using it. Input is capped at 1 MiB, output cannot expand, and binary controls are rejected. Result previews stop at 65,536 characters. No automatic clipboard read, history, file scan or network activity is added.

## Automated verification

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **189 tests passed in 1.491 seconds.** Nine new tests cover default/optional trimming, exact CRLF/CR/LF and Unicode/BOM preservation, ASCII-only collapsing, each blank-line policy, empty/single-line/terminal-newline counts, input limits/binary controls, bounded previews with full numbered publication, all 24 option combinations for idempotence/non-expansion, safe names and cancellation.
- Final native Debug build passed, including the window-specific completion callback. The existing App Intents metadata-skipped notice remains.
- Astro reported zero errors/warnings/hints; all seven pages built and passed local links/assets, canonical metadata, landmarks and pinned Air hashes.
- Independent filesystem assertions verified all three live outputs byte-for-byte, preserving the earlier copies: 38-byte LF text, 41-byte CRLF text and 12-byte unchanged CRLF text.

Logs: [core](text-cleanup-core.txt), [native build](text-cleanup-build.txt), [site](text-cleanup-site.txt).

## Live native observations

1. Opened Text Cleanup from the compact everyday launcher. Empty input disabled Preview Changes, and Try Example populated the fixed 47-byte sample without reading the clipboard.
2. Enabled leading trim, space/tab collapsing and Keep one. Preview produced 38 bytes with three changed lines and one removed line. The original remained available in Input, and the result editor was read-only with its own accessibility label.
3. Saved while Input was selected. The result was written to `/tmp/CloakTools-Text-Cleanup-Verification/Cleaned text.txt`, and the preview returned to Result.
4. Polished the options card to align with the editor width. A narrower window retained readable controls and visible action buttons.
5. Repeated with CRLF input. The reviewed result was 41 bytes; saving created `Cleaned text 2.txt` without replacing the first output. Independent byte assertions confirmed CRLF endings.
6. Removed all lines from a whitespace-only input. Result was empty, Copy Result was disabled and Save Text remained available. Changing the blank-line policy immediately cleared the prepared result and restored Preview Changes while preserving input.
7. Previewed `Clean text` with a CRLF ending. The interface reported No changes needed and retained the 12-byte result. Saving produced `Cleaned text 3.txt`.
8. The native editor originally consumed the first Return after saving. The final correction releases first-responder ownership in the specific operation window. In the final build the successful save focused the window; **one Return activated Done and returned to New Files**. Escape also closed the audited Base64 window from its filename field.

Screenshots: [reviewed result](../../assets/screenshots/text-cleanup-result-dark.png), [numbered save](../../assets/screenshots/text-cleanup-saved-dark.png), [current launchers](../../assets/screenshots/ux-audit-new-files-dark.png).

## Website and boundaries

Install, Support, Source, Privacy, the homepage screenshot and feature copy describe the current implementation. Desktop and 320 × 740 mobile guide checks showed readable wrapping without horizontal overflow (document width equaled viewport width). Mobile Menu opened, Escape closed it, and animation replay became enabled after the finite animation completed. No browser warnings/errors were observed in the checked session. Temporary viewport overrides and tabs were cleared; the development server was stopped.

This pass did not invoke Copy Result, save the empty result through the UI, exercise native oversized-paste rejection interactively or test cancellation during a long UI operation. The corresponding core bounds/cancellation and full publication are tested. Exact minimum dimensions, full VoiceOver and the broader appearance/accessibility/release matrix remain in the audit record. Preferences and Chrome/Mail defaults were unchanged. No deployment, installer or public release was produced.
