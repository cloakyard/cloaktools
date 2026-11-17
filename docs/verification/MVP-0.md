# MVP 0 verification — 15 November 2026

**Functional MVP 0 is complete as a local development milestone.** The three real integration paths, settings, documentation and independently buildable Air website work. This is not release/distribution acceptance. The limits below are deliberately retained; screenshots and unit tests do not establish every accessibility or filesystem case.

## Environment and build

- Apple silicon; macOS 27.2.1 (26B131).
- Xcode 27.2 (27B52), macOS 27.2 SDK, Swift 6.4.2.
- Target: macOS 27.0, arm64, Swift 6 strict concurrency.
- Node 26.13.1, Astro 7.4.12, exact dependency versions and npm lockfile.
- No valid signing identities from `security find-identity -v -p codesigning`. Local ad-hoc signing succeeds. Xcode explicitly disables hardened runtime for ad-hoc signing.
- Both read-only reference repositories remained clean in `git status --porcelain` after inspection and implementation.

Commands actually run:

```sh
# From the repository root; includes embedded Finder extension
./scripts/build-native.sh

# Shared-core tests
(cd apps/macos/Packages/CloakToolsCore && GIT_CONFIG_COUNT=0 swift test)

# Website types, build, links/assets, metadata, Air provenance
(cd apps/site && npm run verify)
```

Results: native **BUILD SUCCEEDED**; **13 Swift Testing tests passed**, including parameterized checks for all 13 programming languages and eight unsafe filenames (32 individual cases). Website: **0 errors, 0 warnings, 0 hints**, seven static pages, all checked local links/assets and Air hashes passed. The final screenshot update was followed by another site build and link/hash verification. No generated programming file was executed.

## A. Actual Finder → file

Registered and enabled the embedded extension with public `pluginkit` commands documented in the README. Finder's real blank-space context menu in `~/CloakTools Files` exposed the catalog. Created `Untitled.py` and `Untitled 2.py`, both zero bytes, without overwriting. Switched Hello World On in the app, then invoked Finder again **without restarting Finder**. `Untitled 3.py` contained `print("Hello, World!")` and a newline.

After expanding the catalog, the actual Finder menu exposed all 15 formats, including Rust, C and C++. Selecting Rust opened the native dialog and Return created `Untitled.rs` containing:

```rust
fn main() {
    println!("Hello, World!");
}
```

Selected-folder context was inspected, as was Finder's complementary Services submenu. Native `NSPerformService` via `scripts/verify-service.swift` returned `Service invocation accepted: true`; confirmation created `Selected folder proof/Untitled.txt` inside the selected folder. This helper exercises the macOS Services machinery, not a direct call to the operation model.

Preference behavior was also exercised in the final UI: Rust Off, master Off, master On retained Rust Off. Rust was restored On; the master was restored Off at handoff. Other language choices remain On. Selection and preferences survived app relaunches. The screenshots with Hello World On illustrate its optional enabled state, not the initial default.

Automated tests additionally cover custom content, folder/global precedence, immutable request snapshots, reload, unavailable/unwritable destinations, collisions with files/directories/symlinks, and 24 concurrent publications. Code changes required extension re-registration during development; changing preferences did not require a Finder restart.

## B. Actual selected image → native PNG copy

Generated a synthetic 640 × 480 JPEG with `scripts/make-test-image.swift`. Selected it in the real Finder context, chose Convert to PNG, then confirmed in the host. The resulting `Conversion proof converted.png` opened in native Preview. `sips` independently identified PNG, 640 × 480.

Source SHA-256 before and after conversion:

```text
1fdd9a8d2b2ec07e6f1b2b672574810284636cc00786cf9e851a7c1c2b3744bd
```

Source bytes remained unchanged. Core tests independently encode a JPEG, convert with ImageIO, decode the resulting PNG, preserve source bytes, and exercise cancellation. The final conversion dialog was visually checked after the compact redesign. The earlier result screenshot records the original real conversion.

## C. Actual URL events → chooser → explicit app

Used `open -a <built CloakTools.app> '<URL>'`, delivering genuine URL events without changing defaults.

- HTTPS opened the chooser and was dispatched explicitly to Safari. Safari's actual address field displayed the synthetic URL, including its query. Repeated after the final compact chooser redesign using `https://example.com/?from=cloaktools` and keyboard Return.
- HTTP and mailto were selected in the chooser and dispatched to a **separate native registered receiver application**, built from `scripts/fixtures/RoutingProbe.swift`. Its `NSApplicationDelegate` recorded exact received strings. Equality assertions passed for the original HTTP query and mailto recipient, cc, encoded subject, CRLF body, plus sign and punctuation. The receiver log is [routing-events.json](routing-events.json).
- Apple Mail was launched by explicit dispatch, but a compose window/account outcome was not confirmed. No email was sent. Exact mailto preservation is established by the separate native receiver, not claimed as a verified Apple Mail account/draft UI.
- CloakTools did not appear in the destination list. Real installed apps were discovered. Source displayed Unknown.
- Escape dismissed the chooser. Copy Link changed to Copied; pasting the system clipboard into a disposable app field reproduced the exact original URL. That field was cancelled without writing a file.
- Self-exclusion and immediate bounce suppression have core tests. OS opening-error and destination-removed handling are implemented, but a disappearing real app and a real bouncing third-party app were not forced during UI verification.

The probe is test-only, never embedded. It was unregistered after verification; its build bundle was moved to `/tmp/CloakTools-RoutingProbe-proof.app`. Production CloakTools does not write incoming URLs to disk. Rebuild the helper with `scripts/build-routing-probe.sh` to repeat receiver verification.

## Native design and accessibility evidence

The final app uses six sidebar categories with colored SF Symbols, grouped settings and a two-column checkbox grid showing all 13 language choices at the default 900 × 650 pt size. Plain Text and Markdown have independent accessibility labels/values.

New File content is 448 × 344 pt (previously 560 × 460); chooser content is 448 × 430 pt (previously 540 × 470). Windows remain resizable. File paths and error content wrap/scroll rather than forcing horizontal growth. Entry fields, installed-app list, selected checkmarks, progress/results and footer actions have separate visual roles. Glass actions use public SwiftUI `.glass` / `.glassProminent` within `GlassEffectContainer`; text is on semantic readable surfaces. Reduce Transparency or increased contrast selects opaque bordered controls. No custom animation is introduced; explicit animation transactions honor Reduce Motion.

Observed: light/dark rendering, native name focus, Return to create/open, Escape to cancel, retained checkboxes, distinct Plain Text/Markdown AX names, and selected-app state. Dark appearance was also previewed with the debug-only per-app `--appearance=dark` option; system settings were not changed by that option. Full spoken VoiceOver, system Reduce Transparency/Increase Contrast/Reduce Motion toggles, localized strings and extreme resizing remain manual acceptance work.

Screenshots are real captures, not renders/mockups:

- [New Files, light](../../assets/screenshots/settings-light.png)
- [New Files, dark](../../assets/screenshots/settings-dark.png)
- [Compact New File](../../assets/screenshots/new-file-light.png)
- [Compact chooser, light](../../assets/screenshots/link-chooser.png)
- [Compact chooser, dark](../../assets/screenshots/link-chooser-dark.png)
- [Conversion dialog, dark](../../assets/screenshots/convert-dialog-dark.png)
- [Finder result](../../assets/screenshots/finder-created.png)
- [Conversion result](../../assets/screenshots/conversion-result.png)
- [Mail chooser, before design refinement](../../assets/screenshots/mail-chooser.png)

macOS's purple screen-sharing badge and cursor highlights in some captures are system capture UI, not CloakTools controls.

## Website evidence

Air 1.7.4 pinned contract/CSS provenance and hashes are in `docs/air/bundle.json`. All required pages plus License build independently. Root privacy content is shared with the website. No release download or fabricated public source URL is presented. Canonical metadata uses `https://tools.cloakyard.com`; no deployment or DNS action was performed.

Browser checks: 320 × 568, 390 × 844, 768 × 1024, 1024 × 768, 1280 × 720, 1440 × 900, 1920 × 1080 and 844 × 390 layouts had no horizontal overflow. The final updated home was rechecked at 1280 and 390 px; Support, Source, Privacy and 404 were checked at 320 px with no overflow or unnamed links. Install was visually checked at 320 px. Images decoded at their expected dimensions. Native compact navigation opens/closes and Escape returns focus. Light/dark and reduced-motion media emulation were checked. A 200% root text-size test was readable without horizontal overflow; this is text scaling, not a claim of browser zoom testing. A missing route returned actual HTTP 404. Full assistive-technology/WCAG auditing remains open.

- [Desktop overview](../../assets/screenshots/website-preview.jpg)
- [Full desktop page](../../assets/screenshots/website-desktop.jpg)
- [Phone, dark](../../assets/screenshots/website-phone-dark.jpg)
- [200% text, before final native screenshots](../../assets/screenshots/website-text-200.jpg)

Local QA server: `npm run dev -- --host 127.0.0.1 --port 4321` from `apps/site`. Browser overrides were reset and the owned dev server stopped with `npx astro dev stop` after QA. No hosting registration/publication was needed.

## Measured baseline

Final Debug `.app`, including its embedded Finder extension: **2672 KiB allocated on disk** (`du -sk`), approximately 2.61 MiB. Not a compressed download or Release measurement.

A post-interaction idle process sample (`ps`) reported **0.0% CPU**, **139216 KiB RSS** (about 136 MiB), and **1.11 seconds cumulative CPU**. These are single-machine snapshots, not sustained benchmarks, energy measurements or performance guarantees. The core adds no background timer, browser engine, bundled language runtime, cloud client or codec package.

## Remaining gates and next work

No external dependency blocks the local functional milestone. Before a public beta: Developer ID identity/notarization, release packaging and entitlement review; actual macOS 27.0 runtime; full assistive technology/system accessibility settings; protected/cloud/virtual-folder and broader filesystem coverage; more input-format/error/large-image testing; and installation/reinstallation lifecycle checks. Host sandbox strategy and user-selected persistent folder access need review before expanding Finder scope.

Milestone 1 starts with `TemplateSource` and structured-format validity tests, custom-template import with immutable content snapshots, a valid blank PDF constructor, an explicit Finder permission/context matrix, then additional native image conversions. The complete six-milestone roadmap and independent web/mail default/rule/profile requirements are retained in `docs/ROADMAP.md` and `docs/OPEN-WITH.md`. First public beta remains MVP 0 + Milestones 1 and 2.
