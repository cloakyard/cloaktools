# 0.6.0 implementation and audit

Date: 16 November 2026. Environment: Apple silicon, macOS 27.2.1, Xcode 27.2/macOS 27.2 SDK, Swift 6.4.2. Version 0.6.0, build 26. Signing was explicitly deferred by the owner; no paid developer account or valid signing identity is available. This is a local preview, not a completed public beta.

## Implemented

- Three native App Intents: Make Image Fit, Make Markdown Digest and Review Saved File Set. File inputs connect to previous action output, runtime bounds are checked, cancellation reaches workers, security scopes are balanced, and original IntentFile names survive framework materialization. Image/digest actions return files without saving beside sources; saved-set automation opens the existing destination/review flow and honors Developer Tools.
- Configurable Finder-folder code: bounded versioned store, up to 16 folders, Add/Renew/Remove controls, stale/missing feedback, matching actual team/group entitlement checks, path-free change notification and balanced extension leases. Disabled in the ad-hoc build. Cross-process signed access remains unverified.
- Current-event source recognition: only the Get URL event’s system-supplied read-only sender PID can resolve a regular non-self app. Other events and absent evidence remain Unknown. No frontmost guessing or source history.
- Private 0600 exclusive file staging, cleanup established before partial writes, cancellation between chunks, correct nonzero-based Data-slice handling and no-overwrite publication.
- Private media capture workspaces with held leases. Startup recovery removes recognized abandoned captures only; active, unknown and symbolic-link entries are preserved. Destination-side abrupt-crash staging cleanup and power-loss durability remain outside this guarantee.
- Shared UI wrapping/fixed launcher widths and hints; clear unavailable-feature explanations; local ZIP packaging with checksums/manifest and a separate explicit signing/notarization pipeline. Manual updates.

## Automated checks

- Core: 224 tests passed. Includes private publication, nonzero Data slices, cancellation, recovery lease behavior, safe Finder configuration storage, exact fitted bytes and existing tool suites.
- Hosted app: 8 tests passed. Includes bounded fit output/source preservation, variable overflow, Unicode/order, in-memory IntentFile filenames, unsafe/missing input, cancellation and fail-closed event attributes. These invoke intents directly and do not prove Shortcuts process launch.
- Native Debug build and Release preview package: successful. Final package details and independent extracted-signature result are recorded below.
- Website: seven static routes, Astro checks/build, local links/assets, metadata/landmarks and pinned Air checks. Final results are recorded below.

## Live native observations

The actual 0.6.0 Debug app was relaunched before checking new availability messages. Early navigation against a previously running 0.5.9 process is excluded from new-feature evidence.

| Check | Observed result |
| --- | --- |
| Light and Dark | Conversions remained readable with distinct grouping and unclipped launcher labels at 900 × 650 pt |
| Increase Contrast + Reduce Transparency | Native surfaces/separators remained readable; no missing action |
| Reduce Motion | Category navigation remained functional; this is not a frame-by-frame animation audit |
| Keyboard navigation | Visible focus moved from sidebar control to Make It Fit; Space opened the picker; Return calculated a preview; Escape cancelled |
| Image fit | Synthetic 1920 × 1280 PNG produced a 1600 × 1066 JPEG preview of exactly 487,623 bytes under a 500,000-byte limit; cancelled without saving |
| VoiceOver | System toggle visibly enabled and restored; spoken output and cursor traversal could not be verified through this session. Not marked passed |
| General availability | Ad-hoc build explains Shortcuts signing limitation and points to working native tools |
| Finder availability | Additional folders explain their signed-group requirement; no unavailable Add control is exposed |
| Routing | Synthetic NSWorkspace URL reached chooser as Unknown source, then the probe received `https://example.com/cloaktools-source-proof?value=a%26b%3Dc#kept` exactly. No network destination or default-handler change |

Original system states were recorded and restored: Appearance Auto; VoiceOver Off; keyboard navigation Off; Reduce Motion Off; Reduce Transparency Off; Increase Contrast Off. App category returned to New Files. All five pre-test JSON snapshots matched afterward: preferences, templates, file sets, routing rules and default-handler recovery state. Clipboard was not read or changed.

Screenshots: [light](../../assets/screenshots/roadmap-light.png), [dark](../../assets/screenshots/roadmap-dark.png), [contrast](../../assets/screenshots/roadmap-contrast.png), [keyboard focus](../../assets/screenshots/roadmap-keyboard.png), [measured fit](../../assets/screenshots/roadmap-fit.png), [Shortcuts limitation](../../assets/screenshots/roadmap-shortcuts-gate.png), [unknown routing source](../../assets/screenshots/roadmap-source-unknown.png).

## Actual Shortcuts boundary

All three actions appeared in the action library; [catalog screenshot](../../assets/screenshots/roadmap-shortcuts-catalog.png). An owned shortcut named **CloakTools Verification** was created using the synthetic Spectrum.png fixture. Actual execution failed with **LinkDaemon.ProcessRegistry.Errors error 0**, both before and after explicitly restarting the 0.6.0 app and Shortcuts. Focused system diagnostics report `Unable to get teamId from com.cloakyard.cloaktools` while generating bundle identity. No global automation database or security setting was reset to bypass this.

The processing implementation passes hosted tests, but live Shortcuts completion is not claimed. General now explains the unsigned limitation. The named verification shortcut remains available for a future signed retest; the user's pre-existing shortcuts were not modified. Signed Finder-folder runtime and notarization are likewise deferred, not marked complete.

## Remaining acceptance

Edge is not installed; profile routing is not implemented. Positive sender attribution needs a suitable real Get URL sender path; the tested NSWorkspace path correctly remains Unknown. macOS 27.0, spoken VoiceOver, comprehensive minimum-size/long-label/localization, realistic large-file performance and broad filesystem/codec/installer/extension lifecycle coverage remain open. The macOS overlap audit still excludes standalone OCR, basic rename/ZIP, Keep Awake and generic inspection. No public release, repository or deployment was performed.

## Final package and website results

The final Release ZIP is `apps/macos/build/Packages/20261116T165237Z/CloakTools-0.6.0-local-preview.zip`. Size: 5514632 bytes. SHA-256: `61c5ba73aa937d5143ccfd00d01556cd46cf57886676c9d532d7f9b69ff0a123`. Independently extracting it and running deep/strict codesign verification succeeded; app and extension are 0.6.0/build 26, arm64. This confirms the local ad-hoc package integrity, not Developer ID/Gatekeeper acceptance. [Manifest](roadmap-package.json).

Final website verification passed all seven routes. Live Source desktop and Privacy at 390 × 844 px had no horizontal overflow or browser warning/error logs. The new privacy contents link reaches the Shortcuts/Finder section. [Desktop evidence](../../assets/screenshots/roadmap-site-desktop.jpg) and [mobile evidence](../../assets/screenshots/roadmap-site-mobile.jpg). Browser viewport restored and owned tab closed.

Local raw logs (not tracked): `roadmap-core.log`, `roadmap-app-tests.log`, `roadmap-site.log`. The checks and outcome summaries in this record are the portable evidence.

The exact independently extracted Release app was launched successfully through the native UI and restored New Files with the existing saved template. No installer or notarization status is implied. All 368 repository/document Markdown targets resolved.
