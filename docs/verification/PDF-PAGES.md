# PDF page organization verification

Verified 15 November 2026 on macOS 27.2.1 (26B131), Apple silicon, Xcode 27.2 / macOS 27.2 SDK / Swift 6.4.2. Native development preview **0.3.1 (11)**. This record adds to the existing integration evidence; it is not a public-release claim.

## Working path

**File → Organize PDF… (⌥⌘P)**, General Quick Actions and Conversions → PDF Pages open a native file panel for one ordinary PDF. The 580 × 570 pt editor presents a thumbnail rail, original page numbers, independent inclusion checkboxes and a larger focused-page preview. All/None, validated original-page ranges, move up/down, left/right rotation, Reset, filename and destination controls are available. Export Copy writes only included pages, in displayed order, to a new collision-safe file. The saved result offers Finder reveal and explicit Preview opening. General reveal/open preferences are captured at ingress.

The operation captures source bytes once, validates encryption/assembly permissions and form/signature exclusions, and prepares small previews on a worker. Exports use immutable choices and that same capture. Text, page boxes and ordinary annotations stay native PDF content. The original is never changed. The core validates page indices, uniqueness, rotation and nonempty output before publication. There is no dedicated Finder menu/Service for this action in this slice.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **97 tests passed**, including seven new page-organization tests: selected order, omitted pages, relative versus inherent rotation, crop/media boxes, annotations and text; source edits/deletion and collision handling; range bounds/overflow/malformed syntax; invalid/duplicate plans; encrypted/forms/malformed/oversized sources; rotated thumbnail/detail bounds; and pre-cancelled preparation/publication without outputs. Existing assembly, image, routing and file tests also pass. [Core log](pdf-pages-core.txt).
- Native Debug arm64 build: **BUILD SUCCEEDED**, no Swift warnings. Expected unused AppIntents metadata warnings and ad-hoc hardened-runtime notes remain. Built bundle reports 0.3.1 / 11. [Build summary](pdf-pages-build.txt).
- Site: **7 routes**, zero errors/warnings/hints; links/assets, canonical metadata, landmarks and pinned Air hashes pass. [Site log](pdf-pages-site.txt).

## Actual native interaction

Used the existing synthetic `Assembly proof.pdf` fixture generated during the earlier PDF assembly check (137,276 bytes, four pages). No personal document was used.

1. Opened the new action with ⌥⌘P and through Conversions. None disabled Export Copy. An out-of-range `5` submitted with Return showed an error and retained the empty selection.
2. Applied `1, 3-4` with Return. It included exactly three pages and did not export. Focused original page 3, moved it upward twice and rotated it clockwise. The row remained in view after the scrolling refinement, and the larger preview matched the selected rotation.
3. Exported **Page organization proof.pdf** through the native button: **135,962 bytes**, three pages, original-page order **3, 1, 4**, rotations **90°, 0°, 0°**. The first two pages remain 420 × 595 pt; the final image page remains A4. Open in Preview succeeded and displayed the rotated cover followed by the notes.
4. Independent `pdfinfo`, PDFKit text extraction and Poppler rendering confirmed page count/order, rotation, dimensions and selectable text. Rendered and visually inspected all three output pages. The excluded verification page's text is absent from extracted page content; this is not a forensic data-removal claim. [Output evidence](pdf-pages-output.txt).
5. The original SHA-256 remained `fc4d88190eea8566b923af092e8baf57406b31ec4472b434396bd6a9b8ae46a7`.
6. In the DEBUG light appearance, toggled page 2 off, rotated it left, then used Reset: all four pages were included again in original order with no extra rotation. Escape dismissed the unsaved draft without another file. Normal launch/appearance was restored afterward. No link defaults or saved conversion choices were changed.

Screenshots: [dark organizer](../../assets/screenshots/pdf-pages-dark.png), [light organizer](../../assets/screenshots/pdf-pages-light.png), [output in Preview](../../assets/screenshots/pdf-pages-preview.png).

## Design and website review

Native text stays on readable system surfaces; the footer uses the existing Liquid Glass/accessibility-aware action styles. The focused page gets a 768-pixel render while the rail uses 192-pixel thumbnails. A single worker coalesces rapid focus changes, so fast navigation does not create an unbounded set of PDF renderers. Rotated previews fit their rotated bounds. Errors and export actions stay outside the scrolling rail.

Home, Install, Support, Source and Privacy copy reflect the new capability and its limits. The established Cloakyard Air shell and app-specific animation remain. Install was visually checked at 1728 px and 320 px; Support at 320 px. Both narrow pages had `scrollWidth === innerWidth`, with readable wrapped content and no horizontal overflow. [Desktop guide](../../assets/screenshots/pdf-pages-site-desktop.jpg). Test tab closed, viewport override reset and development server stopped. Nothing was published.

## Boundaries and remaining checks

- One PDF, up to 100 MB / 200 pages; total encoded thumbnails capped at 32 MB; output capped at 200 MB after serialization. PDFKit can use additional memory and cannot be interrupted inside a synchronous parse/render/serialization call. Real-world complex-document memory/time behavior needs broader testing.
- Encrypted/restricted PDFs, AcroForm/widgets and document-signature permissions are rejected. Existing assembly exclusions remain. Bookmarks, page labels, document structures and internal navigation are not rebuilt or guaranteed. No OCR, redaction, metadata scrubbing, duplicate-page creation or multi-document page editor is claimed.
- Automated cancellation checks cover pre-cancelled work and existing exclusive publication behavior. Live mid-render cancellation/crash timing, the 200-page UI, minimum-size/long-label stress and actual VoiceOver/Reduce Transparency/increased-contrast interaction were not exhaustively exercised in this slice. Shared controls retain their existing accessibility adaptations.
- Native verification used the Debug ad-hoc build; a 0.3.1 Release/installer/notarization test was not performed. Developer ID signing, supported App Group Finder scopes, Edge/profile routing and earlier release gates remain open.

## API references

Implementation was checked against installed macOS 27.2 `PDFPage.h`, `PDFDocument.h` and the public [PDFPage API](https://developer.apple.com/documentation/pdfkit/pdfpage), including [page thumbnails](https://developer.apple.com/documentation/pdfkit/pdfpage/thumbnail(of:for:)). No third-party PDF runtime was added; Poppler was used only for independent verification.
