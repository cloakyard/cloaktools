# CloakTools design

The development app opens a two-column Workbench. A native source list groups Finder Tools, Files & Templates, Images, PDFs & Media, Text & Sharing, Open Links and optional Developer Tools. Within a category, section headings distinguish related tasks and each row describes the input or result. Search ranks names above capabilities and uses category matches when there is no direct match. A single result displays its ⌘Return shortcut. Back restores the originating category and query. Finder Setup opens Settings directly on Finder. The independent macOS Settings scene uses toolbar tabs and grouped forms, following CloakDrop and CloakRoll. Settings opens with ⌘, and About opens its own tab.

An operation uses the same editor from the Workbench, File menu or Finder. Back keeps the active draft available under In Progress. Independent requests can use a compact secondary window. Empty PDF assembly starts with Choose Files, folder reviews show nested paths, and image fitting places the measured result beside the original. System navigation and action controls use Liquid Glass. Reading surfaces remain opaque. Shared actions switch to bordered styles for Reduce Transparency and Increase Contrast. See the [Workbench verification](docs/verification/WORKBENCH.md) for observed flows and coverage. Earlier compact-window sizes and dated audits below describe their respective builds.

Saved templates use the same native form vocabulary: a star, a small details menu, a standard import panel and a compact details sheet. The sheet edits title/default filename and shows a bounded content preview. Content remains immutable; import a new source to change its bytes. Standard controls provide keyboard and accessibility semantics. Spoken VoiceOver and the complete system accessibility-setting matrix remain release checks.

Clipboard creation uses a 448 × 408 pt operation window with the same Glass footer actions. A filename row precedes a semantic preview card: bounded monospace text or a centered image thumbnail with pixel dimensions. Destination and the copy-preservation note stay visible before creation; longer status/error content scrolls. Return creates, Escape cancels, and the action is available as ⌥⌘N. The preview never changes when the clipboard changes.

Image conversion opens at 448 × 360 pt for PNG or 448 × 432 pt for JPEG/HEIC. A source thumbnail, dimensions and byte count anchor a compact card with native format controls. JPEG/HEIC reveal a labeled quality slider and white/black segmented background choice; the source preview reflects that background. A concise note and output destination fit above the Glass footer. Defaults in Conversions use the same picker/slider components. Status and longer error messages scroll within bounded feedback without moving the primary actions.

PDF assembly uses a 480 × 504 pt window with a named output, a native ordered source list, first-page thumbnails, page counts and an inline Add/Move/Remove toolbar. A destination chooser sits above the Glass footer. Source order is explicit and the success state replaces editing controls. Copy As uses a 448 × 408 pt window with four everyday format choices and two additional developer formats, a bounded monospace preview, byte/item counts and explicit Copy feedback. Long lines scroll within the preview; they never widen the dialog. Both share the same readable surfaces and accessibility-aware action styles.

Open With uses ordered native rows, explicit enable switches and a small row menu for editing/reordering/removal. The 460 × 510 pt rule sheet has two readable cards: identity/destination, then All/Any conditions. The content scrolls as conditions grow; validation and the Glass footer remain visible. The 460 × 450 pt link tester separates input, optional simulated source and the result/reason card. It never opens links. A separate compact one-time input presents the chooser with an explicit bypass explanation. The chooser is 448 × 480 pt to accommodate rule explanations and Create Rule without crowding its app list. Rule/tester screenshots and light/dark observations are in [routing verification](docs/verification/ROUTING-RULES.md).

Default link apps sit near the top of Open With, with separate compact Web links and Email links rows, actual app names and explicit Set Up/Restore actions. The 460 × 380 pt web review and 460 × 330 pt email review show source apps and intended changes on a readable card, with Glass actions below. Restore uses native destination pickers; unavailable prior apps require an explicit choice. Long content scrolls while status and actions stay visible. A system request has a waiting state; results show actual defaults, with Review Again for partial changes. Results contract to 460 × 300 pt for web or 460 × 280 pt for email, with a full-width status card. No switch misleadingly implies a synchronous OS setting.

Destination management uses a 480 × 480 pt sheet for each role: a full-width fallback card, a scrollable app list with real icons and supported schemes, native pin menus, and Glass Cancel/Save Changes actions. Changes stay in a draft until saved. Unavailable saved apps have text explanations as well as a warning color. Pins set presentation order only; the fallback control states its automatic-opening effect directly.

Make It Fit opens at 480 × 520 pt, with original and encoded-result previews, a compact format/size/dimensions card and a collapsed quality/background disclosure showing its current values. Fit status, validation errors, activity and Glass actions stay outside the scrolling content. The primary action changes from Preview Fit to Save Copy only after a measured result; over-budget results keep Save disabled. Text and symbols distinguish success/failure alongside semantic color. A completed copy offers Finder reveal and explicit Preview opening.

## App identity

The Workbench sidebar starts with the 44 pt app icon and CloakTools name below the window controls. A 14 pt gap separates the name from search. Both stay in place as the native Categories and In Progress sections scroll. Settings has a full-width target beneath a divider.

Settings opens at 640 × 600 pt, matching CloakDrop. Preference rows hold controls and current values, with supporting text in section footers. Privacy uses a scrollable reading page with a dated heading, summary and selectable policy text. About centers the 84 pt icon, name, version and credit above Updates and the external links.

The original mark combines a cobalt tool case, beveled silver spanner and fluted amber screwdriver. Eleven editable SVG layers in three depth groups and a native background live in `assets/icon/CloakTools.icon`. A recessed tray sits behind the tools; the raised front rim, case return and brushed latch establish the foreground. Xcode compiles the native icon; macOS supplies glass, lighting and the shape mask. Light, dark, clear and tinted exports come from Icon Composer, not painted imitations. About uses native appearance-specific exports. The circular web adaptation derives from every group's identical source paths in matching paint order. See [asset provenance and regeneration](assets/README.md).

CloakDrop and CloakRoll were studied at their source: foreground geometry, background and dark variants, material configuration, native asset build and website mark. Their filled, legible silhouettes and individual palettes guide CloakTools, with its own tool imagery.

## Family website

The site follows the complete pinned [Cloakyard Air 1.7.5 contract](DESIGN.md) and [hash provenance](docs/air/bundle.json). Air CSS is unchanged. It runs independently of sibling checkouts and uses no external fonts or shaders.

The redesign carries across CloakDrop/CloakRoll's exact header structure (Product, Craft, Privacy, Download, Source), details-based mobile navigation, navigation lifecycle, type scale, two-line hero with a muted second line, generous spacing, section introductions, three open feature columns, two-column Craft/Privacy/Download sections and five-link family footer. Privacy uses the family's policy introduction and table-of-contents layout; 404 uses the same family treatment. Reading pages inherit the same shell. App-specific copy describes only implemented features and the actual local-release state. The install action remains a truthful build guide until a public installer exists.

The unique artwork fans three folded documents—source code, image and outgoing link—into a small tray. It runs once for 2.46 seconds and offers deliberate replay. The pinned shared `mountAirArtwork` helper controls visibility, offscreen pausing and reduced-motion/forced-color/data-saving fallbacks. CSS always supplies the finished composition, including when JavaScript is unavailable. Motion animates transform and opacity only; it does not move surrounding content.

Modern Web Guidance's motion advice, “Keep the final state” and “Prefer to animate `opacity` and `transform`”, informed those choices. Its heavy-work scheduling guidance was not needed for a three-element finite animation. Family navigation uses native in-flow details with a 40rem container threshold, enhanced only with Escape, focus return and section navigation; no application-menu ARIA roles are used.

The full standalone website contract and product appendix are in [apps/site/DESIGN.md](apps/site/DESIGN.md). Source and MIT license now use the maintainer-supplied repository and its main-branch license. Local source and license reading pages remain available for context.

Surface inventory: `docs/air/surfaces.json`. Current website evidence: [Air family audit](docs/air/AUDIT-2026-11-17.md). Native evidence: [UX audit and presets](docs/verification/UX-AUDIT-AND-PRESETS.md). The [Milestone 1 verification](docs/verification/MILESTONE-1.md) and [MVP 0 record](docs/verification/MVP-0.md) remain historical.

Organize PDF opens at 580 × 570 pt (minimum 540 × 520). A thumbnail rail shows original page numbers and independent inclusion checkboxes; the focused page has a larger preview. All/None and a bounded page-range field sit above the editor. Reordering keeps the focused row visible; rotation fits the rotated bounding box. Names, destination, errors, activity and Glass export actions stay visible below. The footer always reports included/total pages; no selection disables Export Copy. Reset restores the original page draft. Render transitions do not animate, respecting Reduce Motion.

Export Media opens at 480 × 550 pt for video and compacts to 480 × 440 pt for audio when the initial layout has not been manually resized. Native AVPlayerView controls sit inside a readable preview card, with duration, bytes and video dimensions below. The output picker contains compatible presets; an incompatible saved recipe remains visibly selected as unavailable until the user chooses another format. A second compact card holds the preset description and name; destination and full-clip limitations follow. Progress, cancellation, validation and Glass actions remain outside the scrolling content. Playback is explicit and pauses on export/close; the successful result offers QuickTime opening.

## UX audit and folder presets

The November 2026 audit unified operation feedback and destination rows. Destination paths use home-relative display, middle truncation, full-path help and accessibility values. They remain above the fixed footer; creation, clipboard, conversion and fitting can change folders without restarting. Errors stay visible near actions and are height-bounded for long messages. Cancellation is neutral and shows Stopping while work finishes. Empty required fields cannot submit. Settings categories reset to the top and language controls adapt to available width.

PNG conversion starts at 448 × 360 pt; JPEG/HEIC at 448 × 432 pt. Switching formats adjusts the default height until the user manually resizes it. Folder presets use a 480 × 400 pt native sheet: preset name, type and filename in one readable card, effective content explanation below, then a persistent destination and Glass footer. Save Preset saves choices only. Use always opens the existing New File review, with its preset origin shown in the heading.

Long website guides have a collapsed native On this page index using Air spacing and link styles. It wraps to one column on narrow screens, supports Escape and moves keyboard focus to the requested section. The family shell, icon and app-specific animation are retained.

## File sets

The 560 × 560 pt file-set window (minimum 500 × 500) keeps a named root folder, a scrollable list of relative paths and a fixed destination/status/Glass-action footer. Each row shows its content policy, with labeled edit/remove actions. Add File and Add Folder use compact 440 pt sheets. The list scrolls to the added/edited item, reserves a scrollbar gutter, and counts implicit parent folders. Programming controls appear only when the set contains built-in code.

Review is a separate step: editing actions disappear, prepared bytes and numbered-folder behavior are explained, and Create Folder is the only publication action. Back returns to editing. Save Set is visually secondary and explicitly saves a reusable structure without creating output. Existing sets show Update saved set / Save Changes; Escape discards the title draft. File (⇧⌘N), General and New Files provide entry points. Native semantic controls, accessibility labels and shared opaque/Glass adaptations remain in use.

## Export recipes

A secondary Save Recipe link sits in each image, fit and media footer, leaving the primary export action clear. The 440 pt native sheet grows with its content: name, tool/settings summary, privacy explanation, then Glass Cancel/Save actions. Reused recipes offer Save Changes with an explicit Save as a new recipe checkbox. Escape discards the draft; inline feedback explains validation or stale edits.

After the primary Make It Fit and Export Media actions, Conversions shows a compact recipe list: tool icon, title and settings, Use, and a labeled actions menu. File → Recreate Export provides the same source review. The picker says Review Source; opening a recipe never starts export, fit calculation or playback. The operation heading names its recipe. Unsupported media keeps the requested choice visible, names the Export as control in its recovery message and disables Export Copy. Choosing a compatible format clears that message. Source limits, fixed destination/status rows and existing window sizes remain in force.

Live light-appearance checks and screenshots are recorded in [export-recipe verification](docs/verification/EXPORT-RECIPES.md). Spoken VoiceOver and the full appearance/accessibility matrix remain release checks.

## First run and optional Developer Tools

Fresh installs present a 460 pt welcome sheet: the native app icon, a short introduction, and one readable card. Everyday tools are labeled Included; Developer Tools has a right-aligned native switch, Off initially. One prominent Glass action saves the choice. The sheet states where to change it later. It does not use personas, separate editions, a multi-page tour or individual feature checklists.

General → Your tools places the same switch near the top. Developer Tools adds its sidebar category and expands existing creation/copy pickers; no empty placeholder tools appear. Programming preferences move out of New Files, whose everyday layout starts with three document types and a Create action. Technical saved items are hidden without deleting them. Existing drafts retain their captured choices. Turning the group back on restores choices, and older installations keep their existing catalog without a new interruption.

Finder offers three common document types and Choose File Type or Template instead of listing every language. The host owns the current catalog. Live light-appearance screenshots, first-run/restart checks and Finder handoff are in [tool-choice verification](docs/verification/TOOL-SELECTION.md).


## JSON and Base64 workspaces

Developer Tools starts with concise JSON, Base64 and Sample Files rows above language/file settings. The same actions appear in File → Developer Tools only while enabled. JSON and Base64 each open a 600 × 600 pt resizable window (minimum 520 × 540), with shared compact heading, native segmented actions, monospaced input/result surfaces and Liquid Glass actions. Validation gives the whole editing area to input and removes Copy Result. Base64 pairs Encode/Decode with an explicit alphabet picker.

Input stays intact. Edits/options invalidate old output and copy feedback immediately; errors explain recovery beside the footer. JSON reports line/column and a focused trailing-comma message. Return remains text input; Command-Return runs the chosen action. Copy Result is unavailable without current nonempty output, and the full result is copied even when its on-screen preview is bounded. Native undo is available while typing. Reduce Transparency and increased contrast use the shared solid-action fallback. Spoken VoiceOver and the full appearance matrix remain release checks.


Base64 now has a compact Text/Image segmented switch in its heading, preserving each mode's draft in the same window. Image mode keeps its own Encode/Decode control and an Include data URL checkbox for encoding. A source card shows a small first-frame preview, detected format, dimensions, bytes and any frame count. The output editor stays bounded and selectable. Decode starts with one text editor; success adds the image card, an editable filename with fixed detected extension, and Save Image. The folder sheet states the exact filename and collision policy. Success replaces the action with Done and offers Show in Finder. Input edits remove stale previews/save actions immediately. Image metadata preservation is stated beside the actions.


## Sample Files workspace

One 560 × 570 pt window (minimum 500 × 540) combines JSON, CSV, Text and Binary with a native segmented picker. The option card shows only a record count or size and units, followed by a filename with fixed extension. A read-only preview takes the remaining space. A concise summary reports exact bytes and, when relevant, record count. Generate precedes Copy Text/Save File; changing content options clears both the preview and save action. Inline validation explains bounds and disables invalid actions. The folder sheet repeats the filename, byte count and numbered-copy policy; success offers Show in Finder and a single Done action. Shared Liquid Glass actions and solid accessibility fallbacks match other operations. Binary uses a small hexadecimal preview and omits Copy Text. [Dark appearance and error-state review](docs/verification/SAMPLE-FILES.md) records the live check.


## Example Copy workspace

The 600 × 600 pt window (minimum 520 × 560) starts with one Choose File action. A source card shows the filename, format and scalar/assignment count after preparation. The transformation summary sits above the output name. An Example/Source segmented control shares one read-only editor, giving the content more room than two narrow panes. Each view has a matching accessibility label and byte count. Source is captured once; Save/Copy explicitly targets the example and returns the preview to Example on success. The retained-key/variable-name note stays visible before sharing. Unsupported files clear the prior result and leave an actionable error with no save action. Shared Glass buttons, numbered-copy publication and a single Done completion match other tools.

## Markdown Digest workspace

An everyday action in New Files and the File menu opens a 640 × 650 pt window (minimum 560 × 600). It begins with one Choose Files action and visible file/count limits. A compact ordered list shows filenames, parent-folder names for local disambiguation, byte counts and accessible move/remove controls. Selecting a file gives its read-only preview; Preview Digest prepares the combined document before revealing Copy/Save. File and Digest share the editor, with matching accessibility labels and a visible full-content review note.

Name, selection or ordering changes require a fresh preview. Failed additions keep existing files and show the error beside the actions. Saving from File view still saves the complete digest and returns to Digest, with a numbered filename, Show in Finder and Done. Shared Glass actions and semantic native surfaces match the family. Live dark-appearance checks caught and fixed an unchanged-name focus commit that cancelled file selection; the same guard was added and exercised in Sample Files. See [verification](docs/verification/MARKDOWN-DIGEST.md) for observed coverage and remaining accessibility/layout checks.

## November audit and Text Cleanup

The second audit prioritizes launch actions over reference material. New Files combines Text Cleanup, Clipboard to File and Markdown Digest in one compact Text & clipboard group. Conversions starts with two image actions and three PDF/media actions; all five fit at the default window size. Recipes/defaults follow, and detailed format limits use a native disclosure. Developer Tools uses the same `ToolLauncherRow` spacing and accessibility naming. File-menu separators distinguish creation, conversion and copying/routing groups.

Base64 Image now begins with a prominent Choose Image action. Inline filename validation disables Save before opening a folder chooser, and decoded status does not contradict an invalid name. Unchanged-value commits retain existing results. Sample Files, Example Copy, Base64 Image and Markdown Digest now share Return-to-Done/Escape-close behavior and editor-focus release on completion. Digest's empty editor explains its next step. The [audit record](docs/verification/UX-AUDIT-TEXT-CLEANUP.md) separates source review from live checks.

Text Cleanup opens at 600 × 620 pt (minimum 540 × 570). One compact options card offers edge trimming, space/tab collapsing and blank-line policy. Input/Result share a native editor; Try Example helps users explore without reading their clipboard. Preview Changes is the first primary action. Results show changed/removed line counts and safe Save/Copy actions; an empty result is explicitly explained. Input stays intact, and option/input edits require another preview. Shared readable surfaces, Glass actions, inline filename feedback and reliable keyboard completion follow the audited pattern.


## File List

File List has a compact everyday launcher at the top of Finder Integration and a File menu action. Its 620 × 600 pt window (minimum 560 × 560) starts with a single Choose Items action. CSV/Markdown uses native segments; optional metadata columns live in a collapsed disclosure with a short summary. Names are mandatory, kind/size start on, and dates/full paths start off. A persistent line explains whether full paths are included.

Items and Export share one workspace. Numbered item rows show name, kind, parent-folder name and file bytes; Add, Refresh, move and remove controls sit inside the list footer. The export preview shows the exact serialized text with an accessibility label, byte count and escaping guidance. Primary actions advance from Choose Items to Preview Export to Save List, with explicit Copy available after preview. Shared Glass actions, inline filename errors, safe numbered output, Show in Finder and one-Return Done match the audited utilities. Errors preserve the captured list, and editing options requires another preview. See [File List verification](docs/verification/FILE-LIST.md) for live coverage and remaining accessibility checks.


## QR creation

Create QR Code joins New Files' Text & sharing group and the File menu as an everyday tool. Its 660 × 600 pt window (minimum 600 × 560) places an editable text/link pane beside the generated image. Try Example supplies a fixed example.com link; Clear is explicit. A neutral empty preview avoids displaying a misleading functional sample code. The image remains opaque black on white, with no decorative overlays or logo cutouts.

The full-width options card contains size and correction segments plus a concise explanation. Default 512 px / Standard suits short messages. Exact UTF-8 byte count, output dimensions and PNG bytes remain visible. Input/options changes remove stale output immediately. Density errors offer a larger image or shorter text; prepared inputs over 512 bytes show a scanner-check hint. Shared Glass actions advance from Create QR Code to Copy Image/Save PNG, then Done. Inline safe-name feedback disables Save, and the folder picker states filename, dimensions and collision behavior. Live checks caught and corrected an initially undersized options-card background. See [verification](docs/verification/QR-CREATION.md) for scan tests and remaining layout/accessibility coverage.

## QR reading workspace

QR Code now has compact Create/Read segments within its shared heading; New Files keeps one row for both actions. Each mode retains its draft while the window stays open. File → Text & Sharing → Read QR Code opens the reader directly. Both are everyday tools.

Read places an orientation-correct image beside selectable, read-only text. Numbered outlines and a matching code menu support multiple results without adding a sidebar. Both pane headings reserve the same height so the selector does not shift one preview lower. The selected outline uses the accent color and thicker stroke. Filename and Copy/Save actions appear only for readable text; no-code and invalid-image states offer a new image instead. No code opens a link automatically.

Choose Another keeps the current result when its panel is cancelled. Accepting a new source clears the old image/text before reading, so a failed read cannot expose stale output actions. Safe-name guidance disables Save, the folder picker identifies code number and byte count, and successful saving offers Show in Finder and Return-to-Done. Glass is confined to action controls; image and text surfaces use semantic backgrounds. See [QR reading verification](docs/verification/QR-READING.md).

## Native capabilities and catalog scope

The [macOS feature audit](docs/MACOS-FEATURE-AUDIT.md) is a prerequisite for adding another tool. Do not add a launcher for basic OCR, renaming, ZIP handling, Keep Awake or file inspection when a suitable macOS workflow already exists. Local execution, a preview and Liquid Glass controls alone do not establish product value.

Consolidate overlapping conversion and utility entry points before broadening the catalog. Keep existing saved workflows and outputs intact during that UX work. Prefer extending a useful workspace, a contextual native handoff or an App Intent over another category or dialog. Explain actual added outcomes such as an explicit byte budget, reviewed structured output or cross-app routing. Developer tools remain opt-in; this audit does not change the user's tool choices.

## Compact navigation after the macOS audit

Version 0.5.9 reduces General to three quick actions: New File, New File Set and Make It Fit. New Files starts with creation and a collapsed built-in catalog, then saved templates before file sets and folder presets. A live review moved templates above empty workflow sections so existing favorites remain easy to find. Markdown Digest stays visible; a native disclosure groups QR Code, Text Cleanup and Clipboard to File under More text tools, with a descriptive subtitle.

Conversions leads with Make It Fit and Export Media, followed by export recipes. Image & PDF tools, Image conversion defaults and Supported files & limits expand independently. The default layout fits the 900 × 650 pt window used in live checks. Native grouped surfaces and concise callout text preserve the established visual hierarchy; operation windows retain their existing Glass controls. File menus use Text & Sharing and Images & PDFs submenus without changing shortcuts or removing actions.

No persistent expansion preferences are introduced. Returning from an operation retains the current view's expanded groups and scroll position; switching categories recreates the compact overview. Developer Tools remains optional, and saved content, defaults and operation handlers are unchanged. See [verification and screenshots](docs/verification/UX-CONSOLIDATION.md) for observed coverage and remaining accessibility checks.

## 0.6.0 availability and accessibility pass

Shortcuts uses one concise General section. This ad-hoc build explains why execution is unavailable and names the equivalent native tools; it does not offer an action known to fail. Additional Finder folders follow the same rule: a concise signed-build explanation in the local preview, native Add/Renew controls and explicit removal review when the entitled store is available.

Shared dialog subtitles wrap without a two-line cap. Launcher buttons retain their width and expose the tool purpose as an accessibility hint. Light/dark and increased-contrast/reduced-transparency layouts were inspected; keyboard focus visibly reaches the launcher and Space/Return/Escape can open, preview and cancel an image-fit operation. Reduce Motion navigation was exercised. All temporary system preferences were restored. VoiceOver was enabled and restored, but spoken output/cursor behavior could not be verified in this session; comprehensive assistive-technology and minimum-size/localization acceptance remain open. See [audit evidence](docs/verification/ROADMAP-IMPLEMENTATION.md).

## Family support

About → Learn more includes a native `Link` labelled Buy me a coffee with the `cup.and.saucer` SF Symbol. `AppLinks.support` owns the family Ko-fi destination. It opens only after an explicit click; no support widget or background request is added.


## Privacy and updates

Privacy is an always-visible sidebar category beside About. It uses native grouped sections for
local storage, files/clipboard, links/permissions, updates, diagnostics/removal and the full policy
link. The main host’s unsandboxed status is explicit. About places the update controls after
app/version information and before support links. Shared update wording matches CloakDrop and
CloakRoll, with automatic checks/downloads off by default and ordinary server request data disclosed.
