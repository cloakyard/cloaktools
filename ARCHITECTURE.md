# CloakTools architecture

The local preview has an arm64 macOS 27 SwiftUI/AppKit host, a local dependency-free Swift package, a sandboxed Finder Sync extension, and an independent static Astro website.

## Ownership and process boundaries

`AppModel` is main-actor isolated and owns preferences and operation windows. `CloakToolsCore` contains Sendable preference/template/request values, atomic disk preference storage, safe publication, ImageIO conversion, URL validation, and loop models. It has no SwiftUI dependency. `FileOperation` owns transient progress, cancellation, errors, and results; these are not persisted as settings.

The host is the sole preferences and template-library writer. Finder menus carry only intent through the registered `cloaktools-action` scheme, explicitly addressed to the containing app. The host validates the scheme/action/path/catalog value and reads settings and the template library once at creation ingress. Confirmation shows the path/content snapshot. Thus no cross-process preference cache, polling timer, or Finder restart is required for preference propagation. The separate optional signed Finder-folder store uses an entitled App Group only for monitored folder bookmarks. Services enter the exact same operation coordinator.

Finder menu construction only reads targeted/selected URLs and creates small menu values. Requests are retained in a bounded tag table because Finder serializes menu items. Image preparation runs in a detached host task before confirmation; encoding and file publication run on a worker only after confirmation. Failures remain in the operation view; cancellation checks bracket native image work and precede publication. Closing a running window requests cancellation and waits for safe completion.

## Scope and access decision

In the ad-hoc preview, Finder Sync monitors the current account’s `CloakTools Files` directory and descendants. Signed builds can additionally restore up to 16 explicitly selected folders from the validated shared store; that cross-process runtime boundary remains unverified. It does not monitor the root filesystem or claim all Finder contexts. `getpwuid` obtains the real account home rather than the extension’s sandbox container. Blank-space context targets the container; a single selected folder targets that folder; selected PNG/JPEG/TIFF/HEIC offers conversion. Sidebar context is supported only where Finder supplies a usable selected folder. The actual blank-space and selected-item contexts are checked separately.

The host is deliberately outside App Sandbox for this local proof, while the extension is sandboxed with user-selected read access. Host filesystem operations still obey POSIX permissions and macOS privacy controls. Extension scope is not a security grant. The user confirms every operation, including externally supplied action URLs. There is no automatic destructive URL command. Before public beta, review sandbox + bookmark/helper design and user-selected scope; do not silently add broad entitlement exceptions.

## Publication

Create a private 0600 staging file with O_EXCL/O_NOFOLLOW in the intended folder, install cleanup before writing, check cancellation between bounded writes, then use `renamex_np(..., RENAME_EXCL)` to atomically publish without overwriting. A collision, including an existing directory or symlink, advances the numeric suffix. A failed operation removes its staging file. Power-loss durability and abrupt-crash staging cleanup are not guaranteed. No code execution occurs. `TemplateSource` separates built-ins from imported content. JSON uses a valid empty object; Core Graphics generates one blank A4 PDF page. Built-in programming starters obey the master/language precedence; imported content is explicit and independent.

`TemplateLibraryStore` atomically stores copied UTF-8 bytes in `templates.json` beside preferences. Import validates regular files and bounds reads to 1 MiB; library limits are 64 items / 16 MiB of content. Each operation owns an immutable snapshot, so editing/removing a saved template cannot change a pending action. Favorites are stable source IDs in migrated preferences. No original file bookmarks or ongoing source access are retained.

Open After Creation is an explicit preference, Off by default. The host targets TextEdit for text/source/imported content or Preview for built-in PDF using `NSWorkspace`, never a shell, script runtime or arbitrary extension association. A viewer failure reports that the file was saved and offers Finder reveal; it does not roll back publication.

ImageIO validates content type, frame count, byte size, and pixel dimensions. `PreparedImage` captures orientation-applied 8-bit sRGB pixels and a bounded thumbnail before confirmation. FileHandle reads are capped even if the input grows; the decoder receives captured data. Output never rereads the source. `ImageConversionOptions` is a value snapshot of persisted defaults, editable within the operation. PNG retains alpha; JPEG/HEIC composite onto a selected solid background and pass native compression quality. Runtime encoder discovery disables unavailable formats. No original metadata is copied. No decoding runs in a Finder callback and no codec libraries are bundled.

## Measured image fitting

`ImageFit` reuses immutable `PreparedImage` pixels, native rendering and ImageIO encoding. `ImageFitOptions` validates byte/dimension bounds and a finite quality floor before work. The initial size fits the requested box without enlarging; integer dimensions preserve proportions to pixel rounding. Each subsequent candidate is rendered from the same original capture.

The bounded search tries quality 1 and the selected floor at each size. A passing floor permits five quality bisection probes; only actually measured passing bytes can become a successful result, so non-monotonic encoder sizes cannot violate the budget. If permitted, a size estimate reduces dimensions, with at most eight size levels and 21 candidate encodes. The final size level reaches the smaller of a 320 px long edge and the initial bounded image. The search favors dimensions before quality and does not claim globally optimal dimensions/quality. PNG skips quality probes. Cancellation is checked around native steps; synchronous ImageIO work cannot be interrupted mid-call.

`FittedImage` holds immutable encoded bytes, options, dimensions and a thumbnail decoded from those bytes. It has no public initializer. A failed budget result remains previewable but `save` rejects it. Publication uses the existing exclusive SafeOutput path and never re-encodes or rereads the source. `ImageFitOperation` owns detached preparation/search/save tasks; UI options stay disabled during work, edits invalidate previews, and Save independently checks its draft still matches the result. Fit options are per-operation and do not mutate regular conversion defaults.

## PDF assembly and Copy As

`PDFAssemblyItem` holds captured PDF bytes, page count and a thumbnail as Sendable values. `LocalFileCapture` bounds source reads and is shared with image conversion. Images are normalized through the image pipeline, then placed on white A4 pages using Core Graphics. PDFKit validates PDFs, including encryption, assembly permission and form/signature exclusions. Worker tasks use separate document instances; no PDFDocument/PDFPage crosses actors. Publication copies pages into a fresh PDFDocument, validates the resulting page count, then uses SafeOutput. Page text, boxes, rotation and annotations are retained; document-level outlines/structures are not merged. Limits cover files, pages and captured byte counts. Additions are atomic from the operation’s perspective; a failed addition keeps the prior selection.

`CopySelection` formats already-selected URLs without filesystem access. Bounds are 200 items, paths under 4,096 UTF-8 bytes and output up to 1 MiB. The host-only `CopyOperation` holds the immutable selection and current text; only its explicit Copy action clears/writes NSPasteboard. It does not read the previous clipboard or keep a history. Shell quoting is pure string formatting, never execution. Copy remains the default Return action after success; Done is a separate dismissal action. Changing formats therefore never assigns Return to closing the dialog.

Multi-item Finder handoffs carry ordered repeated `path` query items, bounded to 131,072 encoded URL bytes. The host validates allowed action/keys, absolute paths, counts and URL structure before presenting a review window. External action URLs cannot publish files or replace the clipboard without confirmation. Finder/Services sort selections by filename; the PDF operation can reorder them.

## PDF page organization

`PreparedPDFPages` holds one bounded, validated PDF capture plus 192-pixel page thumbnails. It has no public initializer. The editor keeps a per-operation order, inclusion flags and relative quarter-turns. Page-range parsing uses original one-based page numbers, bounded to 2,048 UTF-8 bytes and 200 pages; invalid ranges leave the draft unchanged. Focus and export inclusion are separate. Reset reconstructs the draft from the same capture.

Preparation and output use detached workers, sharing the assembly validator and exclusive publisher. Export validates unique in-range indices and rotations before making a new PDFDocument from copied pages; it preserves the captured source rotation and applies the relative turn. No PDFKit objects cross task boundaries. A single coalescing preview worker renders a 768-pixel image of the latest focused page, avoiding a large decoded preview for every page and unbounded render tasks during fast selection. Native PDFKit calls are synchronous; cancellation is checked around steps and before publication. A late cancellation after successful publication still reports the saved output.

The 100 MB input/200-page caps and 32 MB total encoded-thumbnail cap bound captures, not all framework-internal memory. Output is capped at 200 MB after serialization. PDFKit parsing/rendering itself has no hard memory/time budget; pathological or complex PDFs remain a release-performance concern. The app owns up to eight operation windows. No source reread, network fetch, page-history file or automatic persistent recipe is introduced.

## Native media export

`MediaCapture` streams one regular file descriptor into an owner-only temporary directory (0700, capture 0600), up to 1 GB in 1 MiB chunks. It compares descriptor size/modification/change times before and after copying; a detected concurrent edit rejects the capture. This is a bounded capture, not a filesystem transaction against a hostile concurrent writer. `PreparedMedia` retains the capture as an immutable Sendable owner; no AVFoundation object crosses the worker boundary. Capture deinitialization removes its directory. Normal window close explicitly clears playback and source references in `windowWillClose`, covering both titlebar closes and programmatic Cancel/Done. Captures live in private UUID workspaces with an ownership marker and held flock lease. Startup recovery removes only validated abandoned owned captures whose lease can be exclusively acquired. Active, unknown and symlink entries are left alone. This does not sweep destination-side export/file-set staging or guarantee power-loss cleanup.

AVURLAsset uses `forbidAll` external-reference restrictions for inspection, composition and in-app playback. Asset properties load asynchronously. Preparation validates duration, codecs, track counts, dimensions, frame rate and color/media characteristics, then asks the OS for preset compatibility. The main-actor host creates its own AVPlayer from the capture; it never autoplays and disables external playback. A selected export creates a new composition of only audio/video tracks, preserves track ranges and preferred video transforms, and uses AVAssetExportSession's async export and states stream. Cancelling the worker task cancels AVFoundation export. Progress is scoped by operation generation to avoid late updates affecting a retry.

Export writes inside an owner-only staging directory on the destination filesystem. After success it checks output size (up to 2 GB), playability, duration tolerance, expected track counts, codec identities and video dimension bounds. `SafeOutput.publishStagedFile` uses the existing exclusive rename/collision loop without loading large output bytes into memory. The caller cleans the staging directory on success, error or cancellation. Cancellation after a successful rename still reports success; no valid published file is deleted to simulate cancellation. Input/output limits do not bound all framework memory or temporary disk usage mid-encode. Output size is not predicted.

Source metadata and non-audio/video tracks are not copied into the new composition. This is not a guarantee that visible/audible content is anonymous. The shipped app has no bundled codec dependency; native AVFoundation/AVKit handle media. Synthetic fixtures use AVFoundation, and existing ffmpeg/ffprobe tools are used only for independent verification and extra test encodings.

## Clipboard ownership

`ClipboardCapture` reads `NSPasteboard.general` only at a user-invoked clipboard action. The Finder extension never reads clipboard contents; its intent URL carries only the destination. The host captures before opening a folder panel, checks item count/type and the change count, and validates size. No source URLs are dereferenced. Pasteboard reads are synchronous OS IPC; the API has no pre-read byte-length check, so encoded byte limits apply immediately after transfer, before decoding. Access denial/unavailable-content errors are shown without changing system permissions.

The Sendable `ClipboardInput` crosses into a detached task. `ClipboardDocument` validates PNG/JPEG/TIFF frame count and pixel dimensions before rasterizing, applies orientation and makes fresh PNG bytes plus a bounded 384-pixel thumbnail. Text keeps exact UTF-8 content and a bounded character preview. Both remain in memory until confirmation; the same exclusive publication path handles output. An already-open operation never rereads the pasteboard. General reveal/open settings are captured at ingress, and `CreatedFileOpener` explicitly targets TextEdit or Preview. Closing completed/cancelled operations releases their content; no clipboard history or timer is introduced.

## Routing

`NSApplicationDelegate.application(_:open:)` receives real URL events. `NSWorkspace.urlsForApplications(toOpen:)` supplies destinations; bundle identity and resolved app paths exclude self/copies. `NSWorkspace.open(_:withApplicationAt:configuration:)` dispatches explicitly. Incoming strings and mailto fields are preserved. No source evidence is fabricated. A five-second in-memory hash guard prevents immediate bounce-back loops; the guard is rechecked when queued links begin, so a queued bounce cannot auto-dispatch again.

Chooser windows are transient, queued, keyboard operable, and support Copy Link/Cancel. No URL is written by production diagnostics or preferences. The synthetic routing probe is a separate test-only application, never embedded in CloakTools, and records only explicitly delivered test events.

## Family decisions

CloakDrop/CloakRoll were inspected read-only: thin native shells, headless Swift packages, XcodeGen, grouped semantic settings, explicit operation ownership, Air/Astro websites, and honest ad-hoc signing conventions were reused. Their GRDB, downloader tools, USB/device layers, updater/packaging machinery, and Team IDs were not copied. The requested sidebar layout replaces their tabbed settings layout.

## Build and release

`project.yml` is authoritative. Swift 6 strict concurrency; the app embeds pinned Sparkle 2 while the core stays dependency-free. Website dependencies are exact versions with a lockfile. No reference checkout is needed to build. Ad-hoc signing works locally; `scripts/release.py` packages and verifies local ZIPs. An explicit Developer ID mode verifies team/group/runtime signatures, with opt-in notarization/stapling. Sparkle verifies signed feeds and update archives; checks and automatic installation require user action or opt-in. See `docs/UPDATES.md`. Signing credentials, signed runtime validation, distribution entitlement review and public release remain gates. Deployment/DNS were not performed.

## Ordered routing rules

`RoutingRuleStore` is host-only, versioned, atomic and bounded to 64 rules / 512 KiB, with 1–8 validated conditions per rule. It stores patterns and destination bundle IDs/names in `routing-rules.json`, not full link history. The main-actor `RoutingSettings` owns edits; `RuleEngine` is pure and receives compatible bundle IDs from the host. The exact same engine drives live routing and the offline tester.

Each incoming event captures a value snapshot of its rules and destination preferences before queueing. At processing time the host rediscovers compatible destinations and rechecks the loop guard. Explicit one-time override precedes rules; first enabled match precedes the configured per-role fallback, initially the chooser. Missing destinations stop at that rule and explain the fallback; malformed stores fail closed to the chooser. Automatic NSWorkspace failures also reveal the chooser. Duplicate installed bundle IDs use Launch Services’ preferred compatible copy, with a deterministic path fallback. Dispatch rechecks actual-URL compatibility, file existence, bundle identity and self-exclusion.

Automatic successes retain only the rule/fallback label and app name in session memory for settings feedback. The chooser can explicitly create a rule; its proposed web condition uses only the hostname, never a query or message body. Saving a rule does not retroactively dispatch a pending chooser. Test inputs and source simulation belong to the transient sheet. The separate one-time input action supplies an explicit bypass; the tester never launches an app.

Configurable Finder scope sharing remains gated on a valid app-group signing identity. See [Finder access](docs/FINDER-ACCESS.md); no App Group entitlement, broad exception, notification-based path broadcast or cross-container write was introduced in the ad-hoc build.

## Destination preferences

`RoutingDestinationStore` holds a versioned archive of separate web/email preferences, up to 32 unique pins per role and one optional fallback each, bounded to 64 KiB. References contain bundle IDs and display names; executable paths, profiles and accounts are not persisted. Pin ordering is presentation only and never adds incompatible apps or removes other compatible apps.

The compact manager edits a local draft. Save checks the current role against the observed version, preserving newer changes to the other role and rejecting stale same-role edits. Writes are atomic, not cross-process compare-and-swap transactions. A newly selected fallback must still be available when saved. Previously saved unavailable apps remain visible and removable. Runtime and tester use the same `RoutingConfiguration`/`RuleEngine`; an unavailable matching rule never falls through to the fallback. Settings read failures use the chooser, while an explicit one-time bypass remains available.

## Default-handler transactions

`DefaultHandlerCoordinator` owns the review plan and serializes default changes across system consent. Its `DefaultHandlerSystem` protocol separates a tested, main-actor transaction from `WorkspaceDefaultHandlers`, which uses public NSWorkspace discovery and `setDefaultApplication(at:toOpenURLsWithScheme:)`. Status discovery uses synthetic scheme probes without opening them. `DefaultHandlerSettings` refreshes on app activation and explicit Refresh; no background polling or write runs on launch.

Web and email are independent roles. A review captures all current role schemes and history; execution refuses stale observations/history or unavailable destinations. Setup atomically saves all planned prior handlers before the first request, protecting both HTTP and HTTPS if macOS couples a browser change. It never replaces an already-owned scheme’s prior handler. Each request verifies current state and destination identity again; afterward it reads actual defaults, accepts only intended coupled results and stops on unexpected state/error. There is no speculative rollback and no atomic compare-and-swap facility in NSWorkspace. A concurrent external change during a system consent request remains a documented OS boundary.

`HandlerHistoryStore` stores at most three scheme recovery points / 64 KiB in a versioned JSON archive. A point contains the previous optional app and the owning CloakTools identity. Writes are atomic. A preflight write failure prevents all system requests; a cleanup failure preserves the preflight snapshot and reports actual system state. Restoration is explicit and requires current ownership by the running app’s bundle ID and canonical path. It uses a previous compatible app when available (including a moved copy with the same bundle identity), otherwise requires an explicit alternative. Other apps and CloakTools copies are not silently treated as owned.

The review sheet retains its observed state when a destination picker changes. It disables closing/repeated actions while macOS is processing and shows verified current values afterward. Partial results can be reviewed again. The separate `--preview-default-handlers` DEBUG-only fixture changes only an in-memory system adapter and a unique temporary history file. Its UI is explicitly labeled as a preview; it never calls the default-setting API and is excluded from Release builds.

## Folder presets and operation UX

`FolderPresetStore` owns a separate local JSON library, limited to 32 entries and 256 KiB encoded storage. IDs are unique; titles, local URLs, template references and safe stems are validated on both read and write. Saving references a template by ID; using the preset resolves its current content and captures a `CreationRequest` with immutable content/preferences. Missing templates fail explicitly rather than silently switching to blank text. A blank-code policy can only reduce the global Hello World choice; imported templates and valid structured files keep their existing semantics.

The host presents the existing file operation for review. Presets never auto-run, select Finder scopes, grant access or create their destination directory. They store a path rather than a bookmark; users repair moved destinations explicitly. `DestinationRow` keeps the path and Change control outside scrolling content. `OperationFeedback` keeps errors, cancellation and activity beside the footer; error text is bounded and scrollable. Normal cancellation is secondary feedback, while failed operations are errors. Late-cancelled preparation results are discarded. PDF preview cancellation also runs on programmatic window close. Category changes rebuild their form so scrolling cannot carry over from another category.

## File sets and folder templates

`FileSetDefinition` stores up to 32 relative-path entries, template identifiers, a folder name and a blank-code policy. `FileSetStore` atomically persists up to 32 definitions in `file-sets.json`, with a 2 MiB bounded read/write. Definitions never contain an output destination or arbitrary binary files. Template references resolve against the operation's captured library; missing references require an explicit replacement.

`PreparedFileSet` validates all paths and template extensions, applies captured Hello World precedence, then owns up to 16 MiB of exact content. Validation rejects hidden/traversal paths, unsafe components, depth over eight, duplicate IDs, case/canonical-Unicode path collisions, inconsistent directory spelling and file/parent conflicts. Empty folders and implicit parent folders are supported.

Publication creates a private sibling staging directory (0700), writes ordinary files (0600), checks cancellation between items, then uses `renamex_np(RENAME_EXCL)` to publish the entire folder. Existing names retry with a numbered suffix, including concurrent requests and symlink collisions. No merge or overwrite occurs. Normal failure/cancellation removes staging; process termination may leave it. The selected destination's ordinary permissions and filesystem behavior apply; this is not a general folder-import or adversarial filesystem isolation facility.

`FileSetOperation` captures preferences/templates at invocation and separates editable draft, prepared review and publication. Both preparation and writes run off the main actor. Native folder panels use asynchronous presentation, attached to the current window when available. Save Set updates the definition library only; Create Folder publishes output only. A new invocation sees current global preferences, while an existing operation retains its snapshot. Open After Creation intentionally does not launch a set of files; Reveal Created selects its root folder.

## Export recipes

`ExportRecipeOptions` is a typed Codable payload for `ImageConversionOptions`, `ImageFitOptions` or `MediaExportPreset`. It stores output settings only. Recipe identity and title live beside that payload; no source URL, destination, output filename, captured bytes or history is serialized. Fit limits must use whole decimal KB, matching the existing editor without silent rounding.

`ExportRecipeStore` validates at most 32 unique entries, 1–80-character titles and each option payload. Version 1 archives are bounded to 256 KiB, read through `LocalFileCapture` and written atomically to `export-recipes.json`. Unsupported versions, malformed/oversized data and invalid values fail without replacing the library. Upsert reloads current state and compares an update's original value, rejecting stale changes or removed recipes. Save as new uses a fresh UUID. Main-actor app calls serialize ordinary edits; cross-process concurrent writers are not transactionally locked.

`AppModel.useRecipe` reloads the selected definition and snapshots preferences before an asynchronous source picker. It rechecks the eight-window limit when the picker returns. The existing image, fit or media operation captures that fresh source and receives the recipe settings before preparation. Each operation still requires explicit output confirmation; fitting must calculate a new measured result. A saved media preset is retained through preparation and validated against the source's supported choices, never silently substituted. Choosing another compatible preset changes the draft only.

Save Recipe captures current valid settings at invocation. Updating a recipe or deleting its definition does not mutate other open drafts or exported files. The existing safe output/cancellation paths remain authoritative. These are reusable settings, without batch jobs, folder watchers, automatic replay or PDF recipes.

## Tool availability and onboarding

`Preferences` stores `developerToolsEnabled` and `hasChosenTools`. A missing preferences file yields everyday mode and incomplete onboarding. Decoding a legacy file without these keys yields developer mode and completed onboarding, preserving existing behavior. Explicit saved values survive restart. A hidden Developer Tools selection normalizes to General. Mode changes never reset Hello World, per-language choices, favorites or saved definitions.

`ToolAvailability` centralizes visible settings categories, built-in templates, Copy As formats and saved-workflow classification. Programming/JSON built-ins and known source/config extensions are technical; custom content is not inspected. Presets and file sets follow their referenced templates; unresolved references remain visible for repair. This is presentation filtering, not a security barrier or content-execution permission.

The host filters catalog snapshots at operation ingress and rejects an explicit hidden programming request. Copy As and preset editors capture available choices for their draft; toggling mode cannot rewrite an existing operation. Library stores continue retaining every definition. Importing a known technical template while off explains how to enable the group before storing it.

The sandboxed Finder extension has no new preferences-sharing entitlement. Its fixed compact menu offers everyday document types and a catalog handoff. The host reads current preferences when that intent arrives, so enabled developer choices appear without Finder restart or private-path broadcasts. Existing app-group scope limitations remain unchanged.

`ToolWelcomeView` appears from the settings window only for incomplete first-run choice. The single action saves both keys atomically before dismissing; save errors remain visible for retry. An unreadable existing preferences file shows its existing error instead of presenting welcome and overwriting it. No automatic onboarding action changes OS defaults or grants access.


## Developer text utilities

`DeveloperText` provides bounded, pure transformations. A strict JSON parser validates grammar and Unicode escapes while emitting original tokens, so it never converts numbers to floating point or reorders/deduplicates object keys. Top-level scalars are valid. The parser limits input to 1 MiB of UTF-8, nesting to 128 containers and formatted output to 8 MiB. Errors report one-based lines and Unicode-scalar columns, treating CRLF as one line break. Format uses two-space indentation; Minify only removes insignificant whitespace; Validate emits no output. Unpaired escaped surrogates are rejected.

Base64 uses Foundation for encoding/decoding with explicit standard/URL-safe alphabets. Only ASCII whitespace is ignored. Missing padding is supplied, then canonical re-encoding rejects bad padding, non-zero pad bits and mixed alphabets. Decoded bytes must be valid UTF-8; no lossy replacement or file export is offered.

`DeveloperTextOperation` runs transformations off the main actor, cancels on edits/close and verifies a revision before publishing any completion. A fresh stored Developer Tools preference guards entry. Each open operation keeps its availability snapshot. Plain native text views disable rich text, substitutions, spellchecking and detection; input edits reject oversize text, results are read-only and previews are bounded to 65,536 characters. Copy Result writes the complete result only on explicit action. Windows participate in the existing eight-operation limit. No text is persisted or logged.


`Base64Image` captures PNG/JPEG/GIF/WebP/TIFF/HEIC/HEIF using the existing bounded `LocalFileCapture`, retains exact original bytes, and prepares an orientation-aware first-frame PNG thumbnail with ImageIO. It bounds bytes to 10 MiB, every frame's dimensions to 40 megapixels, and frame count to 512. The shared canonical Base64 decoder accepts standard payloads and strictly parsed image data URLs, verifies declared versus detected MIME type, and rejects non-images/SVG. Encoded input is bounded to 14 MiB. No re-encoding of the original image occurs, so metadata, transparency and animation are retained.

`Base64ImageOperation` owns separate input/source/result state inside the Base64 Text/Image workspace. Modes retain their respective drafts for the window lifetime. Revision checks and cancellation prevent stale previews; editing the image input removes any decoded snapshot/save action. Save Image chooses a destination folder after the filename/preview review and publishes exact bytes through `SafeOutput` with numbered collisions. The short publication phase disables edits and refuses window close until its result is known. Source selection, encoding, decoding and saving run on workers. No image file is written merely by decoding.

## Sample files

`SampleFileRequest` accepts only relevant whole-number parameters, validates record/byte limits before allocation and checks unit multiplication for overflow. `SampleFiles` generates deterministic synthetic records using JSONEncoder or a CSV field escaper, repeated ASCII text, or zero-filled bytes. JSON/CSV support 1–10,000 records; text/binary support 1 byte–32 MiB. CSV uses CRLF record endings and quotes delimiters, quotes and embedded line breaks. Preview truncation preserves UTF-8 boundaries; binary gets a 64-byte hex preview. Generation has no filesystem side effects.

`PreparedSampleFile` holds immutable bytes and their bounded preview. `SampleFileOperation` runs generation, text preparation and publication on workers, cancels on edits/close, and checks a revision before accepting completion. Count/size/format edits clear stale results; renaming retains the bytes. Save File first asks for a folder and publishes those exact bytes through `SafeOutput`. The short saving phase disables edits and window closing. Copy Text is explicit and copies complete content; Binary has no copy action. Entry reads the current stored Developer Tools preference and shares the existing eight-window limit. No settings, source paths or history are persisted for this tool.

## Example Copy

`ExampleCopy` captures one selected UTF-8 file up to 1 MiB with `LocalFileCapture`. JSON uses a replacement mode of the existing strict token parser, retaining original key tokens/order/duplicates while replacing string, number and boolean values. Null and containers are kept. The existing 128-level depth and 8 MiB output guards apply, including the trailing newline. Normal JSON formatting/minification/validation behavior is unchanged.

Environment parsing accepts ASCII identifier assignments with optional export and single-line quoted or unquoted values. It does not evaluate expansions or commands. Comments and blank lines are discarded; unsupported multiline/continuation/mixed-quote syntax fails with a line number and no echoed value. Prepared results retain both source and example text only in memory. Previews are bounded at 65,536 Characters; saved/copied content is complete.

`ExampleCopyOperation` captures/prepares and saves on workers with cancellation/revision guards. Source replacement clears old output before loading, including on failure. Compare mode never selects publication bytes: Save/Copy always uses the prepared example, then switches the visible preview back to Example. The native text editor refreshes its accessibility label when switching views. `SafeOutput` preserves existing names and originals; environment output is a visible `.env` file, with no relaxation of shared hidden-name restrictions. Entry checks the stored Developer Tools preference and shares the eight-operation cap.

## Markdown Digest

`MarkdownDigest.capture` reads only 1–32 explicitly selected regular local UTF-8 files through bounded `LocalFileCapture` reads. It rejects direct symlinks, duplicate standardized paths and binary controls; limits are 1 MiB per file and 8 MiB combined. Immutable `DigestFile` values retain captured text in memory. `adding` skips already-included paths when adding other new files, and rejects an entire failed batch without changing existing captures.

Preparation uses the selected order and filename-only, numbered headings. Heading punctuation is escaped and controls are replaced with spaces. Each full source is enclosed in a backtick or tilde fence longer than any matching run in the source; a fixed extension map supplies language hints. Source text, including Unicode and line endings, remains unchanged inside the framing. No source is rendered, evaluated, redacted or traversed. Prepared output is capped at 12 MiB; File/Digest previews are capped at 65,536 characters each. Copy and SafeOutput publication use the immutable complete digest.

`MarkdownDigestOperation` runs capture, preparation and saving on workers with cancellation/revision guards. Content/order/name edits invalidate preparation. Choosing a file for inspection only changes the preview. Successful Copy/Save returns to Digest; failed additions retain the current selection. Closing cancels unfinished work, except the brief publication phase prevents closing. Entry is everyday, shares the eight-window cap, and persists no paths or history. Name observers compare old and new values before invalidating; this prevents unchanged text-field focus commits from discarding a file-picker completion. Sample Files now applies the same guard to its generation inputs.

## Text Cleanup and audited UI states

`TextCleanup` transforms bounded UTF-8 bytes with explicit options: trim ASCII spaces/tabs at line edges, collapse their runs, and keep/collapse/remove empty lines. Its line scanner retains CRLF/CR/LF sequences on retained lines; Unicode bytes are copied intact. Input is capped at 1 MiB, output cannot expand, binary controls are rejected, and cancellation is checked between lines and every 4,096 bytes. Prepared values retain the original input, full output and changed/removed line counts. EOF after a terminator does not count as another empty line.

`TextCleanupOperation` runs preparation and SafeOutput saving on workers with revision guards. Input/options changes invalidate previews; filename edits retain prepared text. One native editor switches between editable original and bounded read-only result. Copy/Save always uses full prepared output, returns to Result, and successful saving releases the embedded editor’s focus so Return activates Done. Empty output can be saved; it cannot replace the clipboard. Nothing is persisted except explicitly saved output. Everyday entry shares the eight-window cap.

Shared `ToolLauncherRow` gives everyday, developer and conversion actions consistent icons, wrapping descriptions and named accessibility actions. Base64 images now have a primary Choose Image action until a source exists, plus inline safe-name validation. Same-value bindings no longer clear text results/save feedback. Newer text/image utilities use Return for Done, Escape for closing outside publication, and window-specific completion focus.


## File List

`FileListExport.capture` validates 1–200 local file URLs and uses `lstat` to capture kind, regular-file byte size and whole-second modification time. It does not open contents or enumerate folders; the final symbolic link is not followed, including broken links. Ancestor path components follow normal filesystem resolution. Direct devices/FIFOs are rejected. Immutable `ListedFile` values retain metadata and selected URLs. Batch additions skip existing paths when new items are also included; any failed capture leaves the earlier selection intact. Refresh replaces all captures only on success.

Preparation preserves the current item order. Name is mandatory; kind/size default on, modified UTC/full path default off. CSV quotes all cells, doubles quotes, uses CRLF record endings and prefixes cells whose first significant scalar is `=`, `+`, `-` or `@` with an apostrophe; whitespace, controls and BOM are skipped for this check. A visible count explains the changed cells. Markdown table cells escape ASCII punctuation and replace line breaks/tabs with visible markers and other controls with a replacement character. Prepared output is capped at 2 MiB and its raw-text preview at 65,536 characters. SafeOutput writes complete immutable UTF-8 content with numbered collisions.

`FileListOperation` runs capture, preparation and publication on workers with cancellation/revision guards. Selection/order/column changes invalidate preparation; filename changes retain bytes. Refresh and failed additions preserve old captures/results until successful replacement. Copy/Save always uses prepared output and returns to Export. Filename validation disables Save, and the specific window releases editor focus after saving for Return-to-Done. The publication phase blocks closing. Everyday entry shares the eight-operation cap; no selection, metadata or export history is persisted.


## QR creation

`QRCodeCreation` accepts up to 1,024 UTF-8 bytes of explicit input. It rejects whitespace-only text and C0 controls other than tab/CR/LF plus DEL, then passes unchanged UTF-8 bytes to the native `CIQRCodeGenerator` with M/H correction. It does not parse, open, fetch or rewrite links. A local software-rendered CIContext supplies the module image. Core Graphics draws integer-sized modules without interpolation/antialiasing into an opaque sRGB white bitmap at the selected 512/1024/2048 size, with at least four additional white modules on each side. Fewer than four pixels per source module is rejected with a larger-image/shorter-text recovery action. ImageIO encodes PNG; no third-party generator is added.

`PreparedQRCode` holds immutable PNG bytes, dimensions and metadata. Workers check cancellation around synchronous framework steps. The host caches a single NSImage preview from those same bytes. `QRCodeOperation` invalidates on byte-exact input/options changes; unchanged focus commits and filename edits retain the prepared image. Copy writes the exact PNG pasteboard representation, and SafeOutput saves the same bytes with exclusive numbered publication. Closing cancels preparation; the short saving phase prevents closing and releases editor focus on success for Return-to-Done. Everyday entry shares the eight-operation cap and persists no input/options/history.

Tests decode ordinary examples with Vision, inspect raw QR descriptor codewords for BOM preservation, and use Core Image's QR detector for the dense maximum-input High-correction fixture that Vision does not detect on this host. Scanner-specific interpretation and physical camera/print coverage are distinct from exact encoded bytes. A leading BOM may be omitted from a scanner's display string.

## QR reading

`QRCodeReading` captures an explicitly selected regular file with `LocalFileCapture`, bounded to 10 MiB. ImageIO validates actual PNG/JPEG/GIF/WebP/TIFF/HEIC/HEIF content, one frame, complete decoding and at most 40 million pixels. It applies orientation while making a scan image at a maximum 4096-pixel long edge, without enlarging. A separate PNG preview is bounded to 768 pixels.

A QR-only Vision request and Core Image QR detector run on the same oriented pixels. Core Image recovers the dense fixture missed by Vision and can add other detected codes. Results are merged by bounding-box intersection-over-union above 0.5, preserving identical text at different locations. Vision text takes precedence; fallback text fills missing values. Valid bounds are clamped to the image, ordered spatially and numbered. Results are capped at 16 codes and 32 KiB of UTF-8 per code; unreadable-text codes remain visible with no export actions. Empty decoded text can be saved as a blank file.

`PreparedQRReading` retains thumbnail PNG, dimensions, decoded strings and normalized locations; original image bytes do not persist after preparation. The AppKit host caches the preview image. `QRCodeReadOperation` uses revision/cancellation guards, clears results for an accepted replacement source, and publishes the selected string as exact UTF-8 via `SafeOutput`. Framework calls are synchronous on a worker; cancellation is checked between steps. Size caps bound input and scan dimensions, not a hard deadline or peak framework memory guarantee.

`QRCodeWindow` owns both operations, shares the eight-window limit and blocks closing during either save. Switching modes retains drafts; closing cancels both. TextKit disables automatic link detection. Copy is explicit, no source is monitored, and no camera, QR history or network path is introduced. Decoded strings reflect scanner interpretation; raw byte payloads and BOM preservation are not promised.

## Navigation consolidation

Version 0.5.9 changes presentation only. SettingsView uses native DisclosureGroup containers and the shared ToolGroupLabel for secondary launchers, catalog details, defaults and limits. ToolLauncherRow continues to call the same AppModel operations. File menu groups retain each action and its keyboardShortcut binding. The existing Developer Tools condition still controls technical menus and catalog items.

Expansion belongs to SwiftUI view state and is not stored. No preferences, library schemas, capture rules, output publication, permission scopes or default-handler logic change. Saved templates, presets, file sets and export recipes use their existing models. The focused verification is a native build, live launcher/menu/shortcut checks and before/after comparisons of existing JSON stores; no new core behavior or mirrored presentation tests are added.

## App Intents and incoming sender evidence

App Intents reuse the native core through detached workers with cancellation propagation. IntentFile URLs hold balanced security scopes; in-memory inputs use the framework materializer. Original IntentFile names supply digest headings/language fences and fitted-output names. Numeric variables are checked again at execution, independent of editor ranges. Image fitting returns only already-measured passing bytes; the digest preserves supplied file order. Neither intent saves next to a source. Shortcuts owns the returned file and any downstream actions.

Review Saved File Set uses stable UUID entities, re-resolves the current definition and Developer Tools availability, and opens the normal folder/review flow. The folder callback rechecks the eight-window cap. It returns after starting review, without claiming creation finished. The local ad-hoc app exposes a signing limitation because LinkDaemon rejects its missing team identity; metadata discovery and hosted perform tests alone are not end-to-end acceptance.

IncomingEventSource reads only current Get URL events and the OS-provided read-only sender PID attribute. It accepts a running regular non-self app identity, never a guessed frontmost app. Source evidence is captured with each routing request and is not persisted as history. Unknown is a normal result, including the exercised NSWorkspace route.


## App updates

`AppUpdater` owns one app-lifetime `SPUStandardUpdaterController`. The SwiftUI command and
About settings observe Sparkle’s KVO state. Update preferences stay in Sparkle’s local defaults,
independent of core persistence. Ed25519 authenticates both feeds and archives, with profiling
disabled and automatic checks/downloads off by default. See [update publishing](docs/UPDATES.md).
