# QR reading verification

Roadmap update: the subsequent [macOS feature audit](../MACOS-FEATURE-AUDIT.md) supersedes this record’s proposed OCR follow-up; standalone OCR is no longer planned. Runtime observations below remain historical.

Verified 16 November 2026 in **0.5.8 (24)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **216 passing core tests**. This extends [QR creation](QR-CREATION.md) and retains the compact controls from the preceding [UX audit](UX-AUDIT-TEXT-CLEANUP.md).

## Behavior and design

New Files → QR Code now opens one everyday workspace with Create/Read segments. File → Read QR Code opens Read directly. Both operations retain their drafts while switching modes; closing discards them. No additional settings row or Developer Tools requirement is introduced.

Read shows the selected image beside selectable, read-only decoded text. Numbered outlines and a matching code menu select among multiple results. A visual audit caught unequal pane-heading heights when the code selector appeared; both now reserve 24 points and their preview edges align. Glass remains on action controls, with semantic backgrounds behind reading content.

Input is one still PNG/JPEG/GIF/WebP/TIFF/HEIC/HEIF image, at most 10 MiB and 40 megapixels. ImageIO applies orientation and caps scan dimensions at a 4096-pixel long edge. Vision and Core Image QR detectors merge by location, preserving identical payloads at distinct positions. The preview is bounded to 768 pixels; up to 16 codes and 32 KiB of decoded UTF-8 per code are accepted. An unsupported-text code remains visible without export actions.

Selecting a replacement clears the old result before reading; cancelling the picker retains it. No-code results retain the image and suggest a sharper image or closer crop. Copy Text is explicit. Save Text writes the complete selected decoded string as UTF-8 with no added newline and safe numbered collisions. Scanner interpretation can omit encoding markers, so raw payload/BOM preservation is not promised. No automatic link opening, clipboard reading, camera, network request or QR history is introduced.

## Automated verification

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **216 tests passed in 1.470 seconds.** Nine new reading tests cover exact link/Unicode/whitespace strings, identical codes at separate locations, detector merging, the dense 1,024-byte High-correction code, orientation, no-code previews and bounded scan dimensions, invalid/truncated/animated/oversized inputs, result bounds, safe text publication and cancellation.
- QR decoding fixtures passed for PNG, JPEG, TIFF, single-frame GIF and HEIC. The non-square JPEG carries orientation 6 and reports swapped dimensions correctly. WebP/HEIF are accepted by the native input contract, but a QR-bearing WebP or distinct HEIF fixture was not exercised in this pass.
- The dense fixture missed by Vision in the creation pass is recovered by Core Image. This is additional native coverage, not a guarantee that every code is detectable.
- Tests remove a captured source before saving and confirm immutable text output. Repeated saving preserves the first file and creates a numbered second file.
- A truncated-image test exposed an inaccurate size error for missing dimensions. Missing/invalid dimensions now report unsupported image; genuine size bounds retain the size error.
- The final native Debug build, including the pane-alignment fix, passed. Existing ad-hoc signing and App Intents metadata warnings remain; no compiler errors occurred.
- Astro reported zero errors, warnings or hints. All seven routes passed local links/assets, metadata, landmarks and pinned Air hash checks.

Logs: [core](qr-read-core.txt), [native build](qr-read-build.txt), [website](qr-read-site.txt), [exact saved text](qr-read-saved-check.txt).

## Live native observations

1. The New Files launcher retains all four Text & sharing rows. QR Code describes both creation and reading. The File menu has Create QR Code and Read QR Code entries; the latter opens an empty reader directly.
2. Created the example.com QR in Create mode, then switched to Read. Loaded a 1200 × 600 synthetic image containing the previously verified URL and multilingual QR images. Exactly two numbered codes appeared, with outlines over the corresponding locations.
3. The first result showed `https://example.com/`, 20 bytes. Entering `bad/name` retained the result, displayed a safe-name error and disabled Save Text. Restoring the name re-enabled saving.
4. Saved the first result as `/tmp/CloakTools-QR-Read-Verification/QR text.txt`. The folder picker identified Code 1, 20 bytes and numbered collision behavior. Completion displayed Saved, Show in Finder and Done.
5. Clicking the second image outline selected Code 2 and displayed Hindi, emoji, Japanese, Arabic and a decomposed accent, totaling 65 UTF-8 bytes. The prior saved status cleared. Switching Create → Read retained the generated URL PNG and the reader's second-code selection independently.
6. Saving Code 2 using the same name/folder created `QR text 2.txt`. Independent byte checks matched both files exactly to their expected strings, including line endings and the decomposed accent. One Return activated Done and returned to New Files.
7. Relaunched the final layout build and opened Read through the File menu. A blank 600 × 400 image returned zero codes, retained its preview and displayed the sharper-image/closer-crop guidance with Choose Image as the primary action.
8. Replaced the blank image with the two-code fixture. Selecting Code 2 from the menu updated the text and highlighted the corresponding outline. Both pane tops and captions aligned in the final design.
9. Selected a 12-byte non-image file named Invalid.png. The old image, code selection and text cleared, a supported-image error appeared, and Copy/Save actions were absent. Escape returned to New Files.
10. App preferences matched the pre-test JSON snapshot exactly. Clipboard contents were neither read nor replaced during live verification, and web/mail defaults were unchanged.

Screenshots: [everyday launcher](../../assets/screenshots/qr-workspace-new-files-dark.png), [multiple-code review](../../assets/screenshots/qr-read-multiple-dark.png), [no code](../../assets/screenshots/qr-read-no-code-dark.png), [invalid image](../../assets/screenshots/qr-read-invalid-dark.png).

## Website and limits

Updated the actual product screenshot and feature copy, Install, Support, Source and shared Privacy page. README, design, architecture, format/API contracts and roadmap now describe reading as implemented, with selected-image OCR next. The 1728-pixel desktop product and guide and 320 × 740 mobile guide were visually inspected. The measured desktop product and mobile guide had no horizontal overflow; browser warning/error logs were empty. The viewport override and test tab were cleared, and the owned development server was stopped.

Screenshots: [product page](../../assets/screenshots/qr-read-site-product-desktop.jpg), [desktop guide](../../assets/screenshots/qr-read-guide-desktop.jpg), [mobile guide](../../assets/screenshots/qr-read-guide-mobile.jpg).

Copy Text, picker cancellation, nil/empty decoded text and cancellation during an active native detector were not exercised interactively. Core checks cover nil/empty result handling and cancellation boundaries; native synchronous calls may finish before cancellation takes effect. Image/text limits do not impose a hard processing deadline or peak memory guarantee. Tiny codes in a reduced image may require a closer crop. Exact minimum-window layout, light appearance, increased contrast, VoiceOver/full keyboard traversal and real camera/printed-code coverage remain open. The screenshot was not itself used as a decoder fixture in this pass. Signing/notarization, Finder scope and other release gates remain unchanged. No publication, installer or third-party dependency was added.
