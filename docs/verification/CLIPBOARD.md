# Clipboard to file — 0.1.1 (3)

Verified 15 November 2026 on Apple silicon, macOS 27.2.1, Xcode 27.2 / macOS 27.2 SDK. This is the next completed Milestone 1 feature; it does not mark the whole milestone or public beta complete.

## Behavior and implementation

**File → New File from Clipboard… (⌥⌘N)**, General/New Files settings, and the scoped Finder submenu all enter the same host coordinator. Finder sends only a destination intent. The host reads one clipboard item at invocation, before any folder picker, and captures the normal reveal/open preferences. An explicit preview and Create action are required before writing.

- Text becomes UTF-8 `.txt` with its Unicode and line endings preserved; up to 1 MiB, without null characters.
- PNG/JPEG/TIFF image representations become one PNG, bounded to 100 MB / 40 megapixels. Native ImageIO applies orientation, preserves alpha, and excludes the original camera/location metadata.
- Copied files/file promises, multiple items, unsupported formats and unavailable clipboard data produce actionable errors. No source URL is fetched or file promise fulfilled.
- The preview uses at most 4,096 text characters or a 384-pixel thumbnail; full content is kept separately in memory. Later clipboard changes cannot alter the operation.
- Expensive image preparation and publication run in worker tasks. No clipboard polling/history, Finder decoding, new dependency or shell execution was added.
- `SafeOutput` provides existing exclusive publication, numbered collisions and cancellation checks. Normal optional opening explicitly uses TextEdit for text and Preview for images.

Relevant files: `ClipboardCapture.swift`, `ClipboardOperation.swift`, `CreatedFileOpener.swift`, `ClipboardDocument.swift`, `ClipboardTests.swift`, the Finder intent/menu, app commands/settings, and synchronized privacy/help/format/roadmap documents. Existing creation now shares the explicit viewer opener.

The dialog is **448 × 408 pt** of content with a 420 × 380 pt minimum, native Glass footer actions, a readable preview card, separately labeled filename, dimensions/byte count and destination. Longer status/errors scroll. Light/dark rendering, keyboard name focus, Return, Escape and image accessibility labels were inspected.

## Actual native integration checks

1. Opened the synthetic `scripts/fixtures/Clipboard note.txt` in TextEdit and copied its contents using native Select All/Copy. It contains Unicode and four CRLF line endings, totaling 74 bytes.
2. Invoked **New File with CloakTools → New File from Clipboard…** from an actual blank-space Finder context in `~/CloakTools Files`. The host preview showed the complete 74-byte text while Hello World was Off.
3. Changed the clipboard by copying only the first line in TextEdit while the preview remained open. Created **Clipboard note proof.txt** from the pending preview. A byte comparison confirmed the output still matched the complete original 74-byte fixture, including all CRLF sequences.
4. Copied the 512-pixel icon's image contents through native Preview Select All/Copy. Invoked **⌥⌘N**, selected the folder through the actual open panel and reviewed a **512 × 512** image preview. Created **Clipboard image proof.png**. Image dimensions were independently inspected with `sips`; with Open After Creation enabled, Preview opened that exact output URL.
5. Copied the resulting file icon in Finder and invoked the action. The app rejected it with the copied-files/unsupported-content explanation, rather than reading the file or saving an icon as its contents.
6. In the final compact layout, named a pending text file **Clipboard note** and pressed Escape. The destination file remained absent.
7. Repeated creation as **Clipboard note proof** in the final build. It created **Clipboard note proof 2.txt**. Both files still matched the original fixture byte-for-byte; the first file was preserved.

Open After Creation was restored Off. Hello World remained Off with retained language choices. The app was returned to the system appearance after using per-app debug appearance flags for captures. Synthetic note/image files remain in the workspace for inspection; no real clipboard content was stored in the repository or verification log.

Actual captures:

- [Compact image preview, light](../../assets/screenshots/clipboard-image-light.png)
- [Compact text preview, light](../../assets/screenshots/clipboard-text-light.png)
- [Compact text preview, dark](../../assets/screenshots/clipboard-text-dark.png)

Any purple badge/cursor highlight in captures comes from macOS screen-sharing UI, not CloakTools.

## Automated checks

```sh
./scripts/build-native.sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
npm --prefix apps/site run verify
```

- Native app + Finder extension: **BUILD SUCCEEDED**. No Swift source warnings in the final build. Xcode's unused AppIntents metadata-extraction notice and local ad-hoc signing notes remain informational.
- Core: **26 tests passed**, including eight new tests, parameterized PNG/JPEG/TIFF coverage and the existing 13-language test. New coverage checks Unicode/CRLF bytes, immutable content, numbered collisions, unsafe names, truncated preview/full output separation, empty text, oversized/null input, valid PNG, alpha, bounded thumbnails, EXIF orientation, source metadata removal, malformed/multiframe rejection, cancellation and strict clipboard intent parameters.
- Website: **0 errors, 0 warnings, 0 hints**; seven pages built, local links/assets and pinned Air hashes passed. Product, Install, Support, Source and the shared Privacy body now describe the implemented feature. The home was checked at 390 px and all four supporting pages at 320 px: the updated clipboard content was present with no horizontal overflow. [Updated full page](../../assets/screenshots/clipboard-website.png). Browser viewport overrides were reset; the owned local QA server was stopped at handoff.

[Core output](clipboard-core-tests.txt) · [Website output](clipboard-site-verification.txt).

## Limits and remaining work

Clipboard IPC is synchronous and has no pre-read byte-length API; encoded limits are checked immediately after transfer and before image decoding. ImageIO cannot be interrupted inside a decode; cancellation is cooperative around native work and before publication. A completed publication remains a successful output.

Actual denied-permission/slow-provider cases, arbitrary third-party clipboard representations, Universal Clipboard behavior and a full spoken VoiceOver/system accessibility matrix were not forced during UI testing. The implementation handles unavailable/changed/denied data and does not change system permissions. The existing signing/notarization, macOS 27.0 runtime and broader Finder-scope acceptance gates still apply.

Next Milestone 1 work: user-selected Finder scopes/persistent access, more native image conversion directions, images-to-PDF/PDF merging and Copy As actions. The full roadmap remains in `docs/ROADMAP.md`.
