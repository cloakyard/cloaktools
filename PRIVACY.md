# Privacy policy

**CloakTools · Updated 23 November 2026**

CloakTools is a local Mac toolkit. It has no accounts, advertising, analytics, telemetry or automatic crash-report uploads. Update checks and downloads are off by default and can be managed in About.

<details>
<summary>On this page</summary>

- [Files and settings](#files-and-settings)
- [QR creation](#qr-creation)
- [QR reading](#qr-reading)
- [File lists](#file-lists)
- [Developer text tools](#developer-text-tools)
- [Folder presets](#folder-presets)
- [File sets](#file-sets)
- [Export recipes](#export-recipes)
- [Shortcuts and Finder folder choices](#shortcuts-and-finder-folder-choices)
- [Links and email](#links-and-email)
- [Network and diagnostics](#network-and-diagnostics)
- [This website](#this-website)
- [Control and removal](#control-and-removal)
- [Questions](#questions)

</details>

## Files and settings

File creation and image conversion happen on your Mac using native frameworks. Manual creation and conversion produce new files. Preferences and your saved template library live in your user Library. This includes whether you completed the welcome choice and enabled Developer Tools. No occupation or developer identity is inferred. Technical templates are shown or hidden using file-type/extension metadata, without inspecting their contents for classification. Turning the group off keeps saved templates, workflows and language choices; it does not delete files or revoke permissions. Importing a template copies its text into the library; changes to the original do not alter that copy. Removing a saved template does not remove the original or any created files. Template imports run once. You confirm the destination for manual exports. If a destination is cloud-managed, that provider may synchronize it under its own policy.

Image conversion keeps the prepared source pixels in memory for its preview and confirmed output. Camera/location metadata is not copied. **Open in Preview** explicitly sends the completed copy to Preview.

PDF assembly captures selected sources in memory, then writes only the confirmed new PDF. PDF page content and annotations are retained in the combined copy; this action is not a PDF metadata scrubber. Original documents stay unchanged. Organize PDF similarly holds one captured document, thumbnails, page choices and rotations in memory until its window closes. Only Export Copy writes the selected pages. It keeps no page-edit history, performs no OCR and is not a metadata-sanitization tool.

In the source build, **Reuse Folder Structure** reads the selected directory tree and offers to save relative folder names in a local file set. **Collect Copies for Sharing** holds selected paths and proposed copy names in memory until the review closes. Saved copies can retain source metadata, including personal information and resource forks. **Compare Two Folders** reads the selected trees, including hidden files, and holds differences in memory for review. Folder comparison and collection have no stored history. While collecting from Finder, the menu bar displays the count. File names and paths are available in the review.

**Copy As** uses selected file/folder names and paths without reading file contents or traversing folders. Only pressing Copy replaces the system clipboard; previews and cancellation do not. Copied paths may contain personal information. CloakTools keeps no copy history and runs no command. Other applications with clipboard access may read what you copy under macOS controls.

Optional Open After Creation passes the saved file to TextEdit (text/source files) or Preview (built-in PDFs and clipboard images). Those applications can retain their own recent-document lists.

**New File from Clipboard** reads one text selection or image only when you invoke that action. CloakTools keeps that copy in memory for the preview and writes it only after you confirm creation. It does not poll, keep a clipboard history, fetch linked resources, or save cancelled clipboard contents. A later copy does not change an already-open preview. macOS clipboard access controls apply.

The development host runs outside App Sandbox; the Finder extension is sandboxed and passes action requests to the host. macOS privacy permissions still apply. Automatic media optimization is limited to a folder you select.

**Optimize Media in development builds** prepares local previews in private temporary directories. Closing the batch releases them. Startup recovery removes recognized abandoned previews. Save Copies publishes the measured bytes in your chosen folder. Replace Original exchanges a same-format result with its source and keeps the original in a visible backup folder beside it. A small recovery record in that folder stores the filename and file identities so you can restore the original after restarting CloakTools. Dragging a prepared output sends a copy to the destination you choose. JPEG XL reconstruction preserves the complete original JPEG, including embedded metadata. After a separate save, Move Original to Trash moves the reviewed source to the system Trash on request. Export recipes contain settings. The command-line tool prints paths, byte counts and outcomes to its caller.

Two optional automations are off by default. **Optimize new clipboard images** checks the pasteboard while CloakTools is running. It can replace a new image with a smaller encoding. It ignores file references and items marked confidential or transient, and checks that the clipboard still contains the same item before replacing it. **Watch a Folder** stores the selected folder path in preferences and checks new media files directly inside it. Smaller copies are saved in its **Optimized Copies** subfolder. Existing files are skipped at startup. General settings let you stop each automation. Cloud-managed folders may synchronize their contents.

Make It Fit holds captured pixels and candidate output bytes in memory while calculating a fit. Preview does not write temporary image files or upload anything. Save writes only the reviewed encoded copy to the displayed destination. Change can select another folder without regenerating the measured result. Per-operation format, size and quality choices are not retained as a separate history. Original camera/location metadata is excluded, with the same image normalization limits as regular conversion.

Export Media makes an owner-only temporary copy of the selected source on your Mac before preview. The capture supports local playback and export even if the original changes afterward. It is removed when the operation closes normally. An app crash or abrupt exit can leave a copy in the account's temporary directory; on a later launch, CloakTools removes only recognized abandoned captures whose private ownership marker and inactive lease can be validated. Active or unknown entries are left alone. Export also uses an owner-only staging directory in your chosen destination, removed on normal completion/cancellation/error. A cloud provider may observe or synchronize temporary files inside a cloud-managed destination under its own policy.

Export Media uses native frameworks. Optimize Media also uses bundled, local codec executables. External media references are forbidden and in-app external playback is disabled. Playback starts only when you press Play; Open in QuickTime explicitly hands the saved output to that application. Source metadata, chapters, subtitles and other extra tracks are omitted, but the actual picture and sound can still contain personal information. The app keeps no media library or export history.

## QR creation

Create QR Code encodes the fields you enter locally. Contact cards, calendar events, coordinates and Wi-Fi credentials come from the form. The tool keeps drafts and the prepared PNG in the window’s memory until you close it. Anyone who receives the code can read its contents, including an encoded Wi-Fi password.

**Copy Image** writes the prepared PNG to the system clipboard. **Save PNG** writes it in the folder you choose. Cloud-managed destinations may synchronize the file under their provider’s policy.

## File lists

File List reads metadata only for files or folders you explicitly select. It captures names, kind, regular-file byte size and modification date in memory. It does not open file contents or scan folder descendants. A selected symbolic link is listed without following its target. Full paths are excluded from exports initially; enabling that column includes selected paths, which can reveal private folder names. Names and other metadata may also be personal. Review the export before sharing.

Preparing a CSV/Markdown list writes nothing. Refresh explicitly reads current metadata again; it does not watch the selected items. Copy List replaces the clipboard only when invoked, and Save List creates a new file in your chosen folder with numbered collision protection. Cloud-managed destinations may synchronize output under their provider's policy. Closing the tool discards captures and output; no file-list history or selected paths are persisted.

## Developer text tools

JSON and Base64 input and results stay in the operation window's memory. CloakTools does not send, save or log this text, keep transformation history, or automatically read the clipboard. Paste is explicit through the native editor. Only **Copy Result** replaces the clipboard; other applications with clipboard access may read that copied text. Closing a tool discards its in-memory session. Base64 is an encoding, not encryption.

Base64 Image mode reads only the image you choose, or the Base64 you explicitly paste. A small first-frame preview is generated in memory. Encoding and decoded-image saving preserve the original bytes, including camera/location metadata and animation; this is not a metadata scrubber. Decoding alone writes no file. Save Image writes a new copy only after you review its filename and choose a folder, with numbered filenames on collisions. Show in Finder is explicit. Cloud-managed destination folders may synchronize the saved image under their provider's policy.

## Sample files

Sample Files builds fixed synthetic JSON/CSV records, repeated text or zero-filled binary data in memory. It reads no source files, contacts, account details or clipboard content; example email addresses use `example.com`. Generate writes nothing. Only Copy Text replaces the clipboard, and only Save File writes the reviewed bytes after you choose a name and folder. Existing files receive a numbered copy. Cloud-managed destinations may synchronize saved output under their provider's policy. Closing the window discards its settings and generated content; no sample history is kept.

## Example copies

Example Copy reads only the JSON or environment file you select. It captures the source and prepares placeholder content locally in memory; neither is logged, uploaded or kept in history. JSON keys, variable names, duplicate names and object/array structure remain and may contain private information. Replacing values is not a guarantee of anonymization or secret detection. Review the example before sharing.

Source/Example previews are read-only. Copy Example writes only the prepared example to the system clipboard. Save Example writes a new file after filename review and explicit folder selection; existing files and the source receive collision protection. Cloud-managed destinations may synchronize output under their provider's policy. Closing the tool discards its in-memory source and result. Environment content is parsed as text and never executed.

## Text cleanup

Text Cleanup processes text you type or paste locally in memory. Try Example inserts a fixed synthetic sample; it does not read the clipboard or files. Previewing preserves the original input and prepares separate output. No input, result or usage history is logged or saved automatically.

Copy Result explicitly writes the full cleaned result to the system clipboard. Save Text creates a new UTF-8 file in the folder you choose, preserving existing filenames with numbered copies. Cloud-managed destinations may synchronize the output under their provider's policy. Closing the window discards its input, options and result. This changes whitespace only; it does not remove private information or detect secrets.

## Markdown digests

Markdown Digest reads only the text files you explicitly choose and keeps captured contents in memory. It does not scan folders, render source markup, execute code, detect secrets or redact content. The output includes full source contents and filename-only headings; source text itself may contain paths or other private information. Review the digest before sharing.

Preparing and inspecting a digest writes nothing. Copy Digest explicitly replaces the system clipboard with the full prepared document. Save Digest writes a new Markdown file in your chosen folder with numbered collision handling. Cloud-managed folders may synchronize it under their provider's policy. Closing the tool discards captured files and prepared text; no digest history or selected paths are persisted.

## Folder presets

Folder presets store a title, local destination path, template identifier, default filename and programming-content preference in the app’s local support directory. They do not copy folder contents or monitor activity. Using a preset captures current template content/settings for a review; nothing is written until Create. Removing a preset leaves its folder and files unchanged. Paths can reveal folder names; no preset sync, telemetry or cloud service is provided.

## File sets

Reusable file sets store their title, proposed folder name, relative paths, template identifiers and blank-code policy in `~/Library/Application Support/com.cloakyard.cloaktools/file-sets.json`. No destination is stored in a set. Preparing a saved set for creation captures its selected template bytes and preferences locally. Importing a structure reads the folder tree you choose.

Creation writes the reviewed files into a private staging folder beside the destination, then publishes one complete new folder. Normal cancellation/failure removes staging; abrupt termination may leave a hidden `.cloaktools-set-…` folder. Created output and saved definitions have independent lifetimes. Removing a definition never deletes output. A set does not widen Finder scopes or grant filesystem access.

## Export recipes

Export recipes store a name and output settings in `~/Library/Application Support/com.cloakyard.cloaktools/export-recipes.json`: image format, quality and background; image-fit limits; or a media preset. They do not store source paths, destinations, output filenames, image/media content or export history. A name you enter can itself contain personal information; the library stays on this Mac.

Saving a recipe creates no exported file and does not change conversion defaults. Using it asks for a fresh source, then opens the normal review and requires explicit export confirmation. The source-capture and temporary-file behavior above still applies. Removing a recipe leaves open drafts, originals and exported files unchanged. No recipe synchronization, folder watching or automatic replay is provided.

## Shortcuts and Finder folder choices

The Shortcuts integration receives only files and parameters supplied to its actions. Image fitting and Markdown digest actions return a result file to Shortcuts without replacing sources or saving a copy beside them. The system may materialize input/result files for transfer. CloakTools keeps no automation input/output history; Shortcuts and any subsequent action have their own storage and sharing behavior. Review Saved File Set opens the existing folder and content review and does not create files silently. Technical saved sets remain subject to the Developer Tools preference. Live Shortcuts execution requires a signed build on the tested Mac and is unavailable in the ad-hoc preview.

In appropriately signed builds, additional Finder folder choices retain the selected folder name, path and security-scoped bookmark in a local shared app-group container, capped at 16 folders. Folder names/paths may be personal. The extension reads this configuration to restore menus, not to scan contents. Change notifications contain no folder path. Removing a choice removes its saved access reference and requests scope refresh; it never deletes the folder or its files. Signed cross-process access still requires runtime validation before release.

## Links and email

Incoming links are held in memory while queued, matched, dispatched or shown in the chooser. CloakTools does not save a browsing history, full URLs, or mailto bodies. It retains in-memory fingerprints of recently dispatched links to detect immediate routing loops. Copy Link writes the original link to the system clipboard. System services may maintain their own logs or clipboard history.

Links are not prefetched, redirects are not resolved, and query parameters are not stripped. Opening a chosen browser or mail application hands it the original URL; its own privacy policies and network behavior then apply. Email links prepare a draft, never send mail. The source application is Unknown unless reliable information is available.

Saved routing rules contain the names, patterns, source bundle identifiers and destination applications you explicitly choose. They live in `routing-rules.json` beside preferences. Patterns can themselves be private; they are never uploaded. The link tester keeps its input and optional simulated source in memory only and performs no network requests or launches. Session feedback remembers only the last rule/fallback label and app name, not the URL. A rule can hand a matching link to its chosen app automatically; missing destinations or unreadable rules return to the chooser.

Default-link setup starts only after you explicitly review and confirm it. CloakTools saves the current app names, bundle identifiers and paths locally in `default-handlers.json` before requesting a system change. These records contain no visited URLs or mail bodies. Web and email are set up separately. Restore is user-invoked and checks current ownership; the app does not reset your defaults on launch, quit or uninstall.

Pinned destination names/identifiers, their order and optional web/email fallback apps are stored locally in `routing-destinations.json`. Saving a fallback lets CloakTools automatically hand unmatched links to that app. Pinning only changes list order. Neither setting changes macOS defaults, and neither records links or discovers signed-in accounts. Missing apps or unreadable destination settings return to the chooser.

## Network and diagnostics

There are no analytics, ads, crash uploads or cloud processing. User-invoked website links open in an external app.

Sparkle 2 checks for updates only when you choose Check for Updates or enable automatic checks in About settings. Automatic checks and automatic downloads are off by default. The app contacts its Cloakyard website for a signed update feed and GitHub Releases (including its asset delivery hosts) for update downloads. These providers receive ordinary request data such as your IP address, requested resource and the app/updater version in the user agent. No system profile, analytics, files or app activity are uploaded. Preferences and the last check time are stored locally. Downloads are signature-verified before extraction; optional automatic installation happens when the app quits.

Standard macOS diagnostics may include information about a failure. Remove personal paths, URLs, credentials, recipients, and message bodies before sharing a report. Test fixtures and screenshots in the repository use synthetic content.

## This website

This static website has no accounts, analytics, advertising, tracking cookies, external fonts, or file uploads. It does not create application browser storage. Local browser and HTTP caches may retain assets. Cloudflare serves this site and may process ordinary request data, including IP addresses, requested paths and browser headers, for delivery and security under its [privacy policy](https://www.cloudflare.com/privacypolicy/). The project does not add a separate analytics pipeline.

External links, including Cloakyard, GitHub, and Ko-fi, have their own policies. They are contacted only when you choose to follow a link; no external widgets are embedded.

## Control and removal

Restore your preferred web/email defaults before uninstalling, if CloakTools currently handles them. Then quit CloakTools and remove its app bundle. Disable the Finder extension and Services if they remain listed by macOS. You may delete `~/Library/Application Support/com.cloakyard.cloaktools` to remove preferences, saved templates, folder presets, file sets, export recipes, routing rules, destination choices and default-app recovery records. Created files remain wherever you saved them; uninstalling does not delete them.

## Questions

Use the [repository support guidance](https://github.com/cloakyard/cloaktools) and [security reporting instructions](https://github.com/cloakyard/cloaktools/blob/main/SECURITY.md). Do not include personal files, paths or credentials in public reports.

## QR reading

Read mode opens only an image you explicitly select, up to 10 MiB and 40 megapixels. Native image processing and QR detection run locally. The window keeps a reduced preview, filename, dimensions, code locations and decoded text in memory; it does not retain the full original bytes after reading. It does not access the camera, read the clipboard automatically, upload images, open decoded links or keep a QR history.

The reader initially conceals decoded Wi-Fi text. **Show encoded text** reveals it. **Copy Text** and file export include the complete selected result, including any encoded password. Contact and calendar documents can also be saved as .vcf or .ics for manual import. Saving creates a new file in the chosen folder. Cloud-managed destinations may synchronize the file under their provider’s policy. Closing the window discards the result.
