# CloakTools roadmap

The local preview contains MVP 0 plus Milestone 1 templates, structured blank documents, clipboard-to-file, native image conversions, PDF assembly, Copy As and Milestone 2 ordered link rules/testing and default-handler setup/restoration and destination preferences, plus Milestone 3 image fitting, PDF page organization and focused media exports, plus Milestone 4 folder presets, related file sets, reusable export recipes, synthetic sample files, reviewed configuration examples and Markdown digests. First public beta = MVP 0 + Milestones 1 and 2. No dates or public-download promises are implied.

## Product scope after the macOS audit

The [macOS feature audit](MACOS-FEATURE-AUDIT.md) governs future work. Prefer Finder, Preview, QuickTime, Safari, TextEdit, System Settings and Shortcuts for tasks they already handle. Standalone OCR, basic batch renaming, generic ZIP tools, Keep Awake and general file inspection are removed from the active roadmap. Existing overlapping tools enter maintenance/consolidation; they are not automatically expanded or removed.

**Implemented in 0.5.9:** compact General quick actions, creation/templates first, prioritized fitting/media workflows and secondary text/image/PDF groups with preserved menus, shortcuts and saved workflows. See [UX consolidation verification](verification/UX-CONSOLIDATION.md).

**Implemented in 0.6.0:** bounded App Intents for fitting, digests and file-set review; configurable signed Finder folders; conservative event-source recognition; private/cancellable output staging; abandoned media-capture recovery; verified preview packaging and an explicit release pipeline. [Verification](verification/ROADMAP-IMPLEMENTATION.md) separates implementation from live coverage.

**Signing deferred by the owner:** Developer ID/notarization, signed Finder lifecycle tests and live Shortcuts execution. Shortcuts discovery succeeds, but LinkDaemon rejects the ad-hoc app identity on the test Mac. The app explains the limitation and directs users to the working native tools.

**Remaining external/manual checks:** Edge is not installed; no profile dispatch is shipped. macOS 27.0 runtime, spoken VoiceOver, comprehensive minimum-size/localization, broader filesystem/codec coverage and repeated installation/extension lifecycle tests still need their respective environments. No excluded native-overlap tools are queued. Further features must show a specific gap in macOS.

## Tool selection

- **Implemented:** first-run everyday tools with optional Developer Tools, a persistent General switch, a dedicated language-settings category, consistent catalog filtering and non-destructive migration for existing installations.
- **Implemented:** local JSON format/minify/validate and standard/URL-safe Base64 text encode/decode and image/data-URL encode/decode with preview and safe saving inside the optional Developer Tools group. Sample Files and Example Copy now join this group. Everyday tools remain available in either mode.

## MVP 0 — Integration foundation

Native sidebar settings and restoration, persistent Hello World precedence, 15 text/source templates, scoped Finder menus and Services, native JPEG/PNG → PNG copies, genuine incoming HTTP/HTTPS/mailto chooser, local privacy, documentation and Air website. Acceptance requires actual integration paths, not only scaffolding. See verification for observed outcomes and limits.

## Milestone 1 — Files and Finder

- **Implemented:** 13 programming languages plus text, Markdown, valid blank PDF and JSON; [capability/encoding table](FORMATS.md) and format-aware output tests.
- **Implemented:** imported UTF-8 single-file templates with exact content, favorites, editable titles/default names and immutable operation snapshots. Templates are never executed; custom content is independent of built-in starters.
- **Implemented:** optional Open After Creation via explicit TextEdit/Preview destinations.
- **Implemented:** clipboard text/image to file through File/Quick Actions and scoped Finder menus, with a compact preview, immutable capture, UTF-8/PNG output and safe publication.
- **Implemented:** single-frame PNG/JPEG/TIFF/HEIC input to PNG/JPEG/HEIC, native quality/background controls, saved defaults and immutable image previews.
- **Implemented:** mixed PDF/image assembly, explicit source order, add/remove/move controls, preserved PDF page content, A4 image pages and safe publication.
- **Implemented:** previewed Copy As for full paths, names, file URLs, shell arguments, Markdown links and JSON path lists.
- **Reviewed:** [Finder context/access matrix](FINDER-ACCESS.md), current scope and app-group signing requirements. Configurable scopes/bookmarks remain gated on a valid team signature/provisioning; broad cloud/virtual-folder and lifecycle coverage remain unverified.

Configurable Finder scope code is implemented in 0.6.0: up to 16 selected folders, Add/Renew/Remove, versioned bounded shared storage, fail-closed stale/missing bookmarks and balanced extension leases. It remains disabled in the ad-hoc preview and is not accepted as runtime-complete until the signed boundary and lifecycle matrix pass. The workspace and Services remain available.

## Milestone 2 — Open With

- **Implemented:** native web/mail chooser, independent explicit default-handler setup/review, actual status and guarded user-invoked restoration. Live setup, normal web/mailto ingress, restart and restoration were verified on macOS 27.2.1; broader OS/installer lifecycle coverage remains a release gate.
- **Implemented:** installed compatible destination selection, independently ordered web/email pins, availability feedback and explicit fallback app/chooser choices; ordered exact-host/subdomain/path/scheme/source and To-recipient-domain rules, All/Any, enabled state and visible priority.
- **Implemented:** local rule tester with destination/reason and no open/network activity, explicit one-time bypass, chooser rule creation, unavailable-app/error fallback and a verified real bounce-back loop.
- Verify Edge application routing. Profile destinations only where both cold/running behavior is supported and tested.
- Implement the full [Open With contract](OPEN-WITH.md), including identity separation and bypass/privacy limitations.

The existing QR, File List and Text Cleanup implementations remain available, with their native overlap documented in the audit. Verify Edge application routing when Edge is available; profile destinations still require real cold/running checks. Finder scopes remain gated on app-group signing.

## Milestone 3 — Conversion depth

- **Implemented:** Make It Fit for native images: target format, maximum bytes and dimension bounds, quality floor, optional further reduction, measured preview and exact-byte safe publication.
- **Implemented:** PDF page inclusion/ranges, reordering, relative rotations, focused previews and safe copy export.
- **Maintenance/consolidation:** existing image conversion and PDF tools substantially overlap with Preview/Finder. No generic editor or additional primitive conversions are queued; new work must demonstrate a concrete gap.
- **Implemented:** full-clip H.264 MP4 up to 720p/1080p and AAC/M4A audio, per-source capability checks, playback, progress/cancellation and safe publication.
- **Implemented:** synthetic image and focused media input/output matrices; broaden real-world codec/color and large-file performance coverage before release.

Prefer system frameworks. Broad codec bundles and full Office rendering require separate explicit dependency decisions.

## Milestone 4 — Repeatable workflows

- **Implemented:** explicit folder presets for a destination, file type/template, name and blank-code policy, with review before creation and global Hello World Off precedence.
- **Implemented:** editable related file sets and reusable folder templates, with validated nested paths, exact-content review, whole-folder publication and numbered collisions.
- **Implemented:** reusable image, fit and media export recipes, fresh-source review, explicit confirmation, compatibility feedback and stale-edit protection.
- **Implemented:** Sample Files generates deterministic JSON/CSV records and exact-size text/binary files, with bounded previews, explicit copying/saving and safe numbered output. Available only inside optional Developer Tools.
- **Implemented:** Example Copy for JSON and environment files, with placeholder values, source/example comparison, visible retained-key guidance and safe publication.
- **Implemented:** everyday Markdown Digest combines explicitly selected UTF-8 files with ordering/removal, captured file/digest previews, literal fenced contents and safe numbered Markdown copies.
- **Deferred:** reviewed project archives require explicit exclusions and an inclusion review beyond Finder Compress. Generic ZIP/unzip is out of scope.
- **Implemented, signed runtime deferred:** Make Image Fit, Make Markdown Digest and Review Saved File Set App Intents, with bounds, original filenames, cancellation and existing Developer Tools filtering. Unit execution and Shortcuts discovery pass; actual Shortcuts execution is blocked by missing signing identity on this Mac. No separate automation engine.

Folder preferences must never override global Hello World Off. Operations snapshot settings/content before beginning.

## Milestone 5 — Everyday utilities

- **Implemented:** everyday Text Cleanup with line-edge trimming, space/tab collapsing, blank-line policies, original/result comparison, changed-line feedback and explicit copying/safe saving.
- **Implemented:** optional Developer Tools for JSON formatting/minification/validation and Base64 text/image encoding/decoding, with bounded local processing, image/data-URL previews, safe image saving, explicit copying and actionable errors.
- **Implemented:** everyday File List exports explicitly selected metadata to CSV/Markdown with optional columns, ordering, refresh, exact previews and safe publication.
- **Implemented:** everyday QR creation with literal UTF-8 input, side-by-side preview, 512/1024/2048-pixel PNG, Standard/High correction, density feedback, explicit copying and safe numbered export.
- **Implemented:** everyday QR reading from selected still images, with orientation-aware previews, numbered code selection, reviewed decoded text and safe text export.
- **Not planned:** standalone OCR; use Preview Live Text.
- **Not planned:** basic Keep Awake; use macOS sleep controls or `caffeinate`.
- **Not planned:** basic batch rename, ZIP/unzip or generic file inspection; use Finder.
- **Maintenance/consolidation:** existing QR creation, Clipboard to File and Text Cleanup. QR reading receives no further expansion until native QR workflows are compared interactively.

## Milestone 6 — Advanced routing

- More verified cross-browser destinations only where they exceed native behavior; Safari-only website/profile rules are already provided by Safari. Webmail adapters and optional extensions require a concrete routing gap.
- Routing-rule import/export remains a candidate. A generic file-association manager is out of scope.
- **Implemented:** inspect only the current Get URL event’s system-supplied sender PID and resolve a regular, non-self app. Other events and missing evidence remain Unknown; no frontmost-app guessing or source history. Live NSWorkspace ingress remained Unknown and preserved the exact URL. Positive source attribution still needs a suitable actual sender path.

## Before release

Local preview packaging and the manual-update decision are complete. Developer ID signing/notarization is deferred by the owner. Private file publication and owned media-capture recovery are implemented and tested; abrupt destination-side staging recovery and power-loss durability are not promised. Light/dark, contrast/transparency, reduced-motion navigation and keyboard operation were exercised and settings restored. Spoken VoiceOver, comprehensive minimum-size/localization, macOS 27.0, broader filesystem/codec/performance and installer/extension lifecycle coverage remain open. Site deployment/DNS and public repository creation are separate publication actions. See [release instructions](RELEASE.md).
