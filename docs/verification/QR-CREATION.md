# QR creation verification

Verified 16 November 2026 in **0.5.7 (23)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **207 passing core tests**. The compact interface follows the preceding [UX audit](UX-AUDIT-TEXT-CLEANUP.md).

## Behavior

Create QR Code is available in everyday mode through New Files → Text & sharing and File → Create QR Code. Input and preview remain side by side. Try Example inserts a fixed example.com URL; no link is fetched or opened. Size choices are 512, 1024 and 2048 pixels; Standard correction M and High correction H are supported. The default is 512 / Standard.

Create QR Code prepares an opaque black/white PNG with integer-sized modules and a white scanning border. Input is capped at 1,024 UTF-8 bytes and encoded without trimming or normalization. Whitespace-only input and binary controls are rejected. Modules must occupy at least four image pixels; smaller results offer a larger-image/shorter-text recovery. Prepared input above 512 bytes shows a dense-code scanner-check hint.

Input/options changes clear stale previews. Filename edits retain the prepared image. Copy Image explicitly writes PNG data to the clipboard; Save PNG publishes those same complete bytes with numbered collisions. Inline filename validation disables saving. Successful output offers Show in Finder and Done; one Return closes the window. No source reads, automatic clipboard reads, QR history, network activity or camera access is introduced.

## Automated verification

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **207 tests passed in 1.610 seconds.** Eight QR tests cover link/text/Unicode decoding, exact byte preservation, PNG size/correction combinations, opaque binary pixels and white borders, input/density bounds, rejected controls, safe exact publication and cancellation.
- Native Debug build passed. The existing App Intents metadata-skipped warning remains; no Swift compiler errors were reported.
- Astro reported zero errors/warnings/hints. All seven pages built and passed links/assets, metadata, landmarks and pinned Air hash checks.
- Vision independently decoded URLs, mailto text, leading/trailing spaces, CRLF/tabs, mixed scripts, emoji and composed/decomposed Unicode. All three output sizes and both correction levels decoded for the ordinary fixture.
- Vision's display string omits a leading UTF-8 BOM. The test parses its QR descriptor's byte-mode codewords and confirms the actual encoded bytes, including the BOM. The generator does not normalize text to match a scanner's presentation.
- At 1,024 input bytes with High correction, Vision did not detect the dense code on this host. Core Image's independent QR detector decoded all 1,024 bytes from the 1024-pixel PNG. The implementation retains the input bound, rejects undersized output and exposes the density hint; universal reader compatibility is not claimed.
- Independent inspection of both live saved images verified exact dimensions, byte counts and Vision-decoded UTF-8 payloads. The QR visible in the native Unicode screenshot also decoded to the exact payload.

Logs: [core](qr-core.txt), [native build](qr-build.txt), [site](qr-site.txt), [saved image scan checks](qr-saved-check.txt).

## Live native observations

1. Opened the everyday launcher in New Files. All four Text & sharing tools remained visible in the existing settings window. Empty input disabled Create QR Code; the input editor received focus.
2. Try Example inserted `https://example.com/`. ⌘Return created a 512 × 512 PNG, 6,233 bytes, with the input still visible. The initial options-card background did not align with the workspace; the final build makes it full width.
3. Entered `bad/name`. The existing preview remained, an inline safe-name error appeared, and Save PNG was disabled. Restoring `QR code` re-enabled saving without regenerating.
4. Saved to `/tmp/CloakTools-QR-Verification/QR code.png`. The destination review showed the filename, 512-pixel dimensions and numbered-collision behavior. Completion retained the preview and showed Show in Finder/Done.
5. Replaced the input with 1,024 synthetic ASCII bytes and selected High. The saved state and old QR cleared. At 512 pixels generation reported a larger-image/shorter-text recovery with no output actions. Selecting 1024 and generating succeeded, showing the dense-code hint and 38,175-byte output.
6. Replaced the input with mixed Hindi, emoji, Japanese, Arabic and a decomposed accent (65 UTF-8 bytes). The stale code cleared immediately. High / 1024 generated a 20,693-byte PNG.
7. Saved using the same stem and folder. Output became `QR code 2.png`, preserving the earlier file. Independent Vision scans matched each image's original payload bytes, including the decomposed accent and line endings.
8. One Return activated Done and returned to New Files. No clipboard contents were read or replaced during this verification. Existing app preferences matched the earlier snapshot exactly; no web/mail default changes were requested.

Screenshots: [everyday launchers](../../assets/screenshots/qr-new-files-dark.png), [URL save](../../assets/screenshots/qr-saved-dark.png), [Unicode numbered save](../../assets/screenshots/qr-unicode-saved-dark.png).

## Website and remaining coverage

Updated the homepage's actual app screenshot and feature copy, Install, Support, Source and shared Privacy content. The README, architecture, design, format contract, API notes and roadmap describe creation as implemented and reading as planned. The desktop product/guide and 320 × 740 mobile guide were visually inspected. No horizontal overflow or browser warnings/errors appeared in the checked pages. The viewport override and test tab were cleared; the owned development server was stopped.

Screenshots: [updated product](../../assets/screenshots/qr-site-product-desktop.jpg), [desktop guide](../../assets/screenshots/qr-guide-desktop.jpg), [mobile guide](../../assets/screenshots/qr-guide-mobile.jpg).

This pass did not exercise Copy Image or oversized-paste rejection interactively; the core validates input bounds and saved PNG bytes. Window-edge drags did not produce a measurable resize, so exact minimum-size layout remains unverified. Light appearance, increased contrast, full keyboard traversal, VoiceOver, printed codes and real phone/camera scanners remain open. Browser checks cover the changed pages rather than every historical UI flow. Signing/notarization, Finder scope and broader release gates are unchanged. No public deployment, installer or third-party dependency was added.
