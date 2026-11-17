# Base64 image verification

Verified 16 November 2026 in **0.5.1 (17)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. This extends the [JSON and Base64 text workspaces](DEVELOPER-TEXT.md). The combined implementation now has **153 passing core tests**.

## Scope and UX

Base64 has a compact **Text / Image** switch in its heading. Image Encode accepts PNG, JPEG, GIF, WebP, TIFF and HEIC/HEIF. It captures the selected file, shows a first-frame preview with format/dimensions/size, then explicitly generates standard Base64. Include data URL starts On and supplies the detected image MIME type. Copy Result copies the complete output, including content beyond the 65,536-character preview.

Image Decode accepts standard Base64 or an image data URL. It detects the real image format, checks any declared MIME type and previews before saving. Save Image reviews a filename and destination folder, then publishes exact bytes through the existing non-overwriting writer. A collision gets a numbered filename. Completion offers Show in Finder and one Done action. Editing input invalidates its preview and save action. Text/Image switches retain separate drafts for the window lifetime.

Original bytes, metadata, transparency and animation are kept; previews show the first frame. Image limits are 10 MiB, 40 megapixels per frame and 512 frames. Pasted encoded input is capped at 14 MiB. SVG and arbitrary binary files are unsupported. Text mode remains capped at 1 MiB and offers Standard/URL-safe alphabets. All processing is local, with no automatic clipboard reads or retained input history.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **153 tests passed in 1.316 seconds** in the final run. Seven new image tests cover exact bytes and MIME detection for PNG/JPEG/GIF/TIFF/HEIC, orientation-aware dimensions, first-frame previews with animation preservation, WebP, wrapped data URLs, MIME mismatches, unsupported/corrupt/non-image input, byte/text/frame limits, immutable capture, safe names and collision-safe publication. The initial 146-test JSON/text suite remains green.
- Native Debug build succeeded. The existing App Intents metadata-skipped notice remains; no new compiler diagnostics were reported.
- Astro reported zero errors/warnings/hints, built seven routes and passed local links/assets, canonical metadata, landmarks and pinned Air hashes.

Logs: [core tests](base64-image-core.txt), [native build](base64-image-build.txt), [website](base64-image-site.txt).

## Live native observations

The image workflow was reviewed in the system's current dark appearance, with the same 600 × 600 pt window and shared Glass actions. Text was reviewed earlier in light appearance.

1. Chose the locally generated `Fixture.webp`. The preview showed its blue geometric image, 640 × 480 dimensions and detected WebP format. Encoding produced a 1,419-byte `data:image/webp;base64,…` result.
2. Pressed Copy Result, switched to Image Decode, pasted through the native clipboard, and decoded. The preview matched the source. No file was written during decoding.
3. Named it `Round trip image` and explicitly selected the temporary verification folder. The UI confirmed `Round trip image.webp` and offered Show in Finder.
4. The saved file was **exactly equal to all 1,046 original source bytes**. SHA-256: `bb1146363fb69121ceaa0484a01976c5f82f8246696aa2790b7461be9c0a2431`.
5. Editing the input removed the decoded preview, saved status and Save Image action. Invalid Base64 produced an image-specific recovery message. A PNG data-URL prefix around WebP data explained the MIME mismatch and did not offer saving. Correcting the prefix recovered the preview.
6. A text-mode draft survived switching to Image and back. Returning to Image retained its reviewed draft too.
7. Saving again under the same name created `Round trip image 2.webp`. Both outputs matched the source byte-for-byte; the first output stayed intact. The final completion layout has a single Done action.

Test outputs are contained in `/tmp/CloakTools-Image-Base64-Verification`. No user source images were used. Native copy testing placed the synthetic image's data URL on the clipboard; restoration of its prior native contents is not claimed. Test windows were closed, the app returned to New Files, and its preferences matched the snapshot taken immediately before image UI tests. Existing template/workflow libraries and system link defaults were not changed.

Screenshots: [encoding](../../assets/screenshots/base64-image-encode-dark.png), [final saved image](../../assets/screenshots/base64-image-saved-dark.png).

## Website and remaining checks

The local Install/Support/Source/Privacy pages describe both text and image modes, data URLs, review-before-save, original metadata retention and limits. Desktop and 320 × 740 browser previews were inspected; mobile document width matched the 320 px viewport with no horizontal overflow. The responsive override was reset, temporary tabs closed and the owned dev server stopped after verification.

Screenshots: [desktop guide](../../assets/screenshots/base64-image-guide-desktop.jpg), [mobile guide](../../assets/screenshots/base64-image-guide-mobile.jpg).

Core tests cover bounds and animation preservation; live UI exercised a static WebP. Large-editor performance, copying beyond the preview limit, other real-world image/animation inputs, VoiceOver and the full appearance/contrast/minimum-size matrix remain broader release checks. This is an ad-hoc signed local preview; notarization and distribution are not part of this change.
