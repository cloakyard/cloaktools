---
layout: ../layouts/Reading.astro
title: Install
description: Install the CloakTools public beta or build it from source.
---
## Requirements

CloakTools targets **macOS 27 or later on Apple silicon**. Development requires Xcode 27, its command-line tools, and XcodeGen. The current source has been built on macOS 27.2.1 with the macOS 27.2 SDK.

## Install the public beta

1. Download the [CloakTools 0.6.0 beta DMG](https://github.com/cloakyard/cloaktools/releases/download/v0.6.0-beta.20261118.2/CloakTools-v0.6.0-beta.20261118.2.dmg). The [release notes](https://github.com/cloakyard/cloaktools/releases/tag/v0.6.0-beta.20261118.2) include the build number and SHA-256 checksums.
2. Open the disk image, drag CloakTools to Applications, eject the image and open the installed copy.
3. This beta is ad-hoc signed and unnotarized. If macOS blocks first launch, review [Apple’s instructions](https://support.apple.com/en-us/102445) before choosing whether to open it.
4. Choose **Settings → About → Check for Updates**. Automatic checks and downloads are optional. Future updates arrive through a signed feed.

## Build from source

Clone the [source repository](https://github.com/cloakyard/cloaktools), then build from its root:

```sh
git clone https://github.com/cloakyard/cloaktools.git
cd cloaktools
./scripts/build-native.sh
open apps/macos/build/Verify/Build/Products/Debug/CloakTools.app
```

This produces a local ad-hoc signed development app. It is not a notarized public release. No developer Team ID is built into the project.

## Choose your tools

On a fresh installation, CloakTools asks which tools you want. **Everyday tools** are always included. Leave **Developer Tools** Off for a simpler catalog, or turn it On to include JSON, Base64, Sample Files and Example Copy, code files, language starters and technical copy formats. Choose **Start Using CloakTools**. The welcome screen appears once.

Change the switch anytime in **General → Your tools**. When enabled, a **Developer Tools** sidebar section holds JSON, Base64, Sample Files and Example Copy alongside Hello World and per-language settings. All everyday document, image, PDF, media and link tools remain available. Turning the group off keeps your saved templates, workflows, favorites and language choices; open operations keep their captured settings.

Older installations keep Developer Tools On so their existing catalog stays available.

## Find your tools

**General → Quick actions** offers New File, New File Set and Make It Fit. **New Files** puts creation and saved templates first, followed by file sets and folder presets. Expand **Built-in file types** for the small document catalog. Programming choices remain in New File when Developer Tools is enabled.

**Conversions** starts with Make It Fit and Export Media, followed by saved export recipes. Expand **Image & PDF tools** for Convert Image, Assemble PDF and Organize PDF. Image conversion defaults and supported-file limits have their own expandable rows.

Markdown Digest stays visible under **New Files → Text & sharing**. Expand **More text tools** for QR Code, Text Cleanup and Clipboard to File. The File menu groups these actions under **Text & Sharing**, with conversion and PDF actions under **Images & PDFs**. Existing keyboard shortcuts still work without opening the groups.

## JSON and Base64

Open either tool in **Developer Tools** or **File → Developer Tools**. Paste text, choose an action, then click the blue button or press **⌘Return**. Return alone inserts a newline. **Copy Result** copies the complete result; input stays intact, and editing clears outdated results. Everything runs locally, with no saved text history.

**JSON** offers Format, Minify and Validate. Formatting preserves number precision, key order and string escapes. Errors include a line and column. **Base64 → Text** encodes/decodes UTF-8 with Standard or URL-safe alphabets. Decoding accepts whitespace and missing padding; use Image mode for image data.

Text input is limited to 1 MiB. JSON supports 128 nesting levels and up to 8 MiB of formatted output. Result previews show up to 65,536 characters; copying includes the full result.

### Base64 images

Choose **Base64 → Image → Encode**, then **Choose Image…**. PNG, JPEG, GIF, WebP, TIFF and HEIC/HEIF are supported. Review the preview and dimensions. **Include data URL** adds the correct prefix, such as `data:image/png;base64,…`; turn it off for plain Base64. Encode, then Copy Result.

For the reverse, choose **Image → Decode** and paste standard Base64 or an image data URL. Decode shows a preview before saving. Enter a filename, choose **Save Image…**, then a destination folder. Existing filenames receive a numbered copy. The saved image preserves its exact original bytes, metadata, transparency and animation; the preview shows its first frame.

Images are limited to 10 MiB, 40 megapixels per frame and 512 frames. Pasted image Base64 is limited to 14 MiB. SVG and arbitrary binary files are not supported. A mismatched data-URL image type produces an error instead of saving a misleading extension.

## Sample files

Open **Developer Tools → Sample Files** or **File → Developer Tools → Sample Files…**. Choose JSON, CSV, Text or Binary, then enter a record count or size. **Generate** shows the content and exact byte count before anything is written. Enter a name, choose **Save File…**, then a destination folder. Existing filenames receive a numbered copy.

JSON and CSV contain 1–10,000 synthetic records with IDs, names, example emails, booleans and notes. Notes include commas, quotes, line breaks and Unicode to try real parsing cases. CSV uses UTF-8, a header and CRLF record endings. The same settings always produce the same content.

Text repeats an ASCII line; Binary creates zero-filled `.bin` data. Both use an exact size from 1 byte through 32 MiB. Choose Bytes, KiB or MiB and enter a whole number; 1 KiB is 1,024 bytes. Text may end mid-line. Zero-filled files are useful for size checks, not representative compression tests.

The preview shows up to 8,192 bytes of text or the first 64 binary bytes as hexadecimal. **Copy Text** includes the whole JSON/CSV/text result. Changing the format, record count or size clears the old preview; Generate again before saving. Everything stays local, with no source-file reads or sample history.

## Example copies

Open **Developer Tools → Example Copy** or **File → Developer Tools → Example Copy…**. Choose a JSON or environment file up to 1 MiB of UTF-8; hidden `.env` files are shown. Compare the read-only **Example** and **Source** previews, name the example, then **Save Example…** and choose a folder. Preparing and comparing write nothing.

JSON keeps keys, order, duplicate keys and nested structure. Strings become `"REPLACE_ME"`, numbers become `0`, booleans become `false`, and null stays null. Environment files named `.env`, `.env.*` or `*.env` keep variable names and optional `export`, replace every value with `REPLACE_ME`, and remove comments and blank lines. Values must fit on one line; nothing is evaluated.

**Keys, variable names and structure are kept. Review them for private information before sharing.** Example Copy does not detect secrets or guarantee anonymization. Copy Example and Save Example always use the complete example, even while Source is selected. Successful copying or saving returns the preview to Example. Existing files receive numbered copies; the source stays unchanged. The default environment output is a visible `Environment example.env`.

Previews show up to 65,536 characters. JSON supports 128 nesting levels and up to 8 MiB of output. Input and results stay in memory until the window closes, with no history or uploads.

## Finder

In **Finder Integration**, open the Finder workspace and enable **CloakTools Finder** through Manage Finder Extension. Its menus cover `~/CloakTools Files` and subfolders. Right-click empty space to create a file, a folder to create inside it, or one PNG/JPEG/TIFF/HEIC to convert a copy. Review the destination before confirming.

For other locations, select a folder or image and use the matching **Finder → Services** command. Hidden services can be enabled in System Settings → Keyboard → Keyboard Shortcuts → Services. Protected folders may require macOS access approval. Search results, virtual locations, and cloud-provider views have different menu availability.

Finder’s New File menu offers Plain Text, Markdown and PDF directly. **Choose File Type or Template…** opens the current catalog, including programming and JSON files when Developer Tools is On.

## Saved templates

In **New Files**, import a UTF-8 text/source template, star your favorites, and set its default filename from the template menu. Finder’s **Choose File Type or Template…** opens the same compact creator. JSON starts with a valid empty object and PDF creates one blank A4 page.

**General → Open after creation** optionally opens text/source files in TextEdit and PDFs and clipboard images in Preview. It starts Off and never executes generated source code.

## Folder presets

In **New Files → Folder presets**, choose **Add Folder Preset…**. Select a folder, name the preset, choose a file type or saved template, and enter a filename without the extension. **Save Preset** saves choices only. Use the row’s **Use…** button or **File → New File from Preset** to review and create a file. The review can change name, type or destination for that one file.

Programming content follows global/language settings or stays blank. Global Hello World Off always wins; custom templates keep their saved content. JSON and PDF retain valid blank structures. The row menu edits/removes a preset without touching its folder or files. Up to 32 presets stay on this Mac. They are explicit starting points, separate from Finder’s monitored workspace. If a folder moves, choose its new location; if a template is removed, edit the preset to select another.

## Create a file set

Choose **File → New File Set… (⇧⌘N)** or **New Files → File sets & folder templates**. Select a parent folder, name the new folder, and review the list of files and subfolders. **Start with…** offers Notes, Python, Rust and C++ examples; they are file collections, without a generated build system or installed dependencies.

Use the pencil to change an item’s relative path or file type, or add files and folders. Changing type adjusts the extension. Parent folders are created automatically. Built-in programming files follow the captured global/language settings, or **Always blank**. Imported templates keep their exact content. JSON and PDF retain valid blank structures.

**Review…** prepares the content without writing files. Check every path, the total bytes and destination, then **Create Folder**. A name collision creates a numbered folder; existing folders are never merged. Change the parent destination from either step, or go Back to revise the set. The created folder can be revealed in Finder; its files are never automatically opened or run.

**Save Set…** stores a reusable structure without creating files. Use it from New Files later; **Save Changes** updates an existing saved set. Removing a saved set leaves created files alone. Sets support up to 32 items, 8 path levels and 16 MiB of prepared content; up to 32 sets stay on this Mac. Hidden names, traversal and conflicting paths are rejected. This does not import existing folder trees or create symbolic links.

## Create QR codes

Open **New Files → More text tools → QR Code → Create** or **File → Text & Sharing → Create QR Code…**. Type or paste text or a link, or choose **Try Example**. Pick a 512, 1024 or 2048-pixel image and Standard or High error correction, then **Create QR Code**. The image appears beside your input so you can review both.

Choose **Copy Image**, or enter a name and **Save PNG…** to a folder. Existing names receive numbered copies. Editing the input or options clears the old code; changing the filename keeps the image. **⌘Return** creates or saves; **Return** closes the completed operation.

This everyday tool accepts up to 1,024 UTF-8 bytes and encodes the text without trimming spaces or rewriting links. PNGs are black on white with a clear scanning border. If a code is too dense, choose a larger image or shorter text. High correction tolerates more damage but increases density; test with your scanner before sharing or printing.

Everything stays local. Links are not opened, and no QR history is kept. Anyone with a code can read its contents. Use Read mode to inspect codes from an image.

## Read QR codes

Open **New Files → More text tools → QR Code → Read** or **File → Text & Sharing → Read QR Code…**, then **Choose Image…**. Review the image beside its decoded text. If several codes are found, click a numbered outline or choose **Code 1**, **Code 2**, and so on. Links are shown as plain text and never opened automatically.

**Copy Text** copies the selected result. Enter a name and choose **Save Text…**, then a folder, to create a UTF-8 `.txt` file. Existing names receive numbered copies. Nothing is added to the decoded string. **⌘Return** chooses or saves; **Return** closes the completed operation. Switching between Create and Read keeps both drafts until the window closes.

Choose one still PNG, JPEG, GIF, WebP, TIFF or HEIC/HEIF image, up to 10 MiB and 40 megapixels. Up to 16 codes can be reviewed. Large images are reduced for reading; if a code is missed, try a sharper image or a closer crop. Animation, multi-page images, PDF and SVG are unsupported.

Everything is processed on your Mac, without camera access, automatic clipboard reads, uploads or QR history. Readers can interpret encoding markers, so this exports decoded text rather than raw binary payloads.

## Text cleanup

Open **New Files → More text tools → Text Cleanup** or **File → Text & Sharing → Text Cleanup…**. Type or paste text, or choose **Try Example**. Select line-edge trimming, space/tab collapsing and whether to keep or remove empty lines. **Preview Changes** prepares a separate result. Only Trim line ends is enabled initially.

Compare **Input** and **Result** and review the changed-line count. **Copy Result** and **Save Text…** always use the complete cleaned result, even while Input is selected. Saving asks for a folder and creates a new `.txt` file; existing filenames receive numbered copies. Editing input or options requires a fresh preview. An empty result can be saved as a blank file.

This everyday tool accepts up to 1 MiB of text. It changes ordinary spaces and tabs while preserving Unicode and the line endings of retained lines. Keep one retains the first blank line in each consecutive run. Cleanup may change indentation or Markdown line breaks, so compare before using structured text. Result previews show up to 65,536 characters; copying and saving include the whole result. Processing stays local, with no automatic clipboard reads or history.

## Markdown digests

Open **New Files → Markdown Digest** or **File → Markdown Digest…**. Choose text files, inspect their captured contents and use the arrows or Remove to arrange them. **Preview Digest** prepares one Markdown document before anything is written. This everyday tool is available with Developer Tools Off or On.

Switch between **File** and **Digest**, then **Copy Digest** or **Save Digest…** to a chosen folder. Both actions use the complete digest and return the preview to Digest. Existing names receive a numbered copy; originals stay unchanged. Changing the name, file selection or order requires another preview.

Choose up to 32 UTF-8 files, at most 1 MiB each and 8 MiB total. Output is limited to 12 MiB. Folders and symbolic-link files are not included. Each section has a filename heading and literal fenced contents, including any embedded Markdown. **Full contents are included. Review before sharing.** Previews show up to 65,536 characters; copying and saving include the whole document. No folders are scanned and no digest history is kept.

## Save what you copied

Copy a text selection or an image’s contents, then choose **File → Text & Sharing → New File from Clipboard… (⌥⌘N)**. Pick a folder, review the preview, choose a name and create a UTF-8 text file or PNG. In the scoped Finder workspace, the same action appears under **New File with CloakTools** and uses that folder.

The action keeps the copy it started with; copying something else afterward does not change the preview. Copy image contents from Preview, rather than a file icon in Finder.

## Prepare an image

Choose **File → Images & PDFs → Convert Image… (⇧⌘K)** or Finder’s **Convert Image with CloakTools…**. Review the preview, then choose PNG, JPEG or HEIC. PNG keeps transparency; JPEG and HEIC offer quality and a white or black background. Save your usual choices in **Conversions → Image conversion defaults**. Each copy starts beside the original and can be opened in Preview. **Change…** chooses another destination without restarting the conversion.

## Make an image fit

Choose **File → Make It Fit… (⌥⌘K)** or **Conversions → Make It Fit**. Choose PNG, JPEG or HEIC, a maximum size in KB, and dimensions to fit within. **Preview Fit** shows actual encoded bytes and pixels before anything is saved. A KB means 1,000 bytes.

Images keep their proportions and never enlarge. JPEG/HEIC try quality down to your chosen floor first. **Reduce further to meet size** allows smaller dimensions, stopping at a 320 px long edge or your smaller starting size. PNG keeps transparency and reduces size through dimensions. The quality/background disclosure shows the current floor and transparency background.

**Save Copy** writes the exact previewed bytes to the displayed destination. **Change…** chooses another folder without discarding the measured result. Changing an option requires a new preview. An over-limit result stays visible with Save disabled; increase the limit or change format. These choices do not alter regular conversion defaults. The same single-frame, 40-megapixel and 100 MB input limits apply.

## Assemble a PDF

Choose **File → Images & PDFs → Assemble PDF… (⇧⌘P)** or select PDFs/images in Finder and use **Assemble PDF with CloakTools…**. Add files, move them into order, remove what you do not need, then choose a name and destination. PDF pages keep their sizes; images fit white A4 pages. Select **Create PDF**, then open the result in Preview.

## Organize PDF pages

Choose **File → Images & PDFs → Organize PDF… (⌥⌘P)** or **Conversions → Image & PDF tools → Organize PDF**. Check the pages you want to include, or enter original page numbers such as `1, 3–5` and choose **Apply**. The list is the export order. Click a page to preview it, move it with the arrows, or rotate it in 90-degree steps. All/None change inclusion; Reset restores the original order, rotations and all pages.

Choose a name and folder, then **Export Copy**. The footer shows how many pages will be exported; an empty selection cannot be saved. Original page numbers stay fixed when you reorder. The source stays unchanged, and a name collision creates a numbered copy. The action accepts one ordinary PDF, up to 200 pages and 100 MB. Bookmarks and internal navigation may not carry over. It is currently available from the app, without a dedicated Finder action.

## Export video or audio

Choose **File → Export Media… (⌥⌘E)** or **Conversions → Export Media**. Select a local movie or audio file and review its duration and dimensions. Native playback controls let you preview it; nothing plays automatically. Choose an available output: **MP4 · Up to 720p**, **MP4 · Up to 1080p**, or **M4A · Audio only**.

Video exports use H.264 and AAC audio when present, keep proportions and orientation, and do not enlarge smaller movies. M4A extracts or converts audio to AAC. Choose a name and folder, then **Export Copy**. Progress and Cancel stay visible. The result is checked before saving and can be opened explicitly in QuickTime. Existing files receive a numbered copy rather than being replaced.

This exports the full clip, without trimming or a promised file size. Inputs are limited to 1 GB and 30 minutes, SDR H.264/HEVC video up to 4096 × 2160 at 60 fps, and mono/stereo AAC/MP3/PCM audio up to 96 kHz. Protected media, HDR, spatial video and multiple video/audio tracks are unsupported. Extra tracks and source metadata are omitted. A private temporary source copy is removed when the operation closes normally; crashes may leave temporary files. No dedicated Finder action is offered yet.

## Recreate an export

Choose **Save Recipe…** in Convert Image, Make It Fit or Export Media. Name the recipe, review its output settings, then **Save Recipe**. This saves choices only; it does not export a file or change your conversion defaults. Source paths, destinations and output filenames are not saved.

Use **File → Recreate Export** or **Conversions → Export recipes → Use…**. Choose a fresh source and review the normal operation window. Convert Image needs **Convert**; Make It Fit needs a fresh **Preview Fit**, then **Save Copy**; media needs **Export Copy**. If a source cannot use a saved media preset, choose an available format explicitly or cancel and choose another source. Nothing plays or exports automatically.

The row menu renames or removes a recipe. In a reused operation, **Save Recipe…** offers **Save Changes** or **Save as a new recipe**. Cancel keeps the saved definition unchanged. An older draft cannot replace a changed or removed recipe; reopen it or save a new copy. Up to 32 recipes stay on this Mac. Removing one leaves output files intact. PDF recipes and batch processing are not included yet.

## File lists

Open **Finder Integration → File List** or **File → File List…**. Choose up to 200 files or folders, arrange their order, then select CSV or Markdown. Expand **Columns** for kind, size in bytes, modified date in UTC and full path. Names are always included; dates and full paths start off.

**Preview Export** prepares the exact output. Switch between **Items** and **Export**, then explicitly **Copy List** or name and **Save List…**. Both actions use the complete export. Saving creates a new file with a numbered name if needed. Changes to columns or item order require another preview.

This everyday tool reads selected metadata without opening file contents or scanning folders. Symbolic links are listed without following their targets; folders and links have blank size cells. Details stay fixed until **Refresh**. A failed refresh keeps the previous list. CSV quotes every field and prefixes formula-like cells with an apostrophe; Markdown escapes markup and shows embedded line breaks/tabs as visible symbols. Full paths can expose private folder names, so review before sharing. Previews show up to 65,536 characters; copying and saving include the full list, up to 2 MiB.

## Copy names and paths

Choose **File → Copy As… (⌥⌘C)** or **Copy As with CloakTools…** in Finder. Preview paths, names, file URLs, shell arguments, Markdown links or JSON, then press Copy. Changing the preview or cancelling leaves the clipboard alone. The action uses names and paths only; it does not read file contents or run commands.

## Links

CloakTools does not change defaults on launch. **Open With** can deliver a test URL through the real macOS event path. You can also target the app directly without changing a default:

```sh
open -a /path/to/CloakTools.app 'https://example.com/'
open -a /path/to/CloakTools.app 'mailto:hello@example.com?subject=Hello'
```

Choose a compatible application and select **Open Once**. Email links only prepare drafts. Source information can be Unknown. Browser-profile destinations remain planned.

## Rules and link testing

In **Open With → Add Rule…**, name the rule, choose Web or Email and its destination, then add conditions. Match all conditions or any one; rules run top to bottom and the first enabled match wins. Use the row menu to edit, reorder or delete a rule. A missing app returns to the chooser with an explanation.

Web rules support exact hosts, explicit subdomains, URL-encoded path prefixes, schemes and source bundle IDs. Email rules support plain To-recipient domains, scheme and source. Unknown source never matches a source condition. A path prefix is literal and case-sensitive: `/work` also matches `/workshop`; use `/work/` for that folder prefix.

**Test a Link… (⌥⌘T)** shows the winning rule or fallback, app and reason without opening or fetching anything. Its optional source is a simulation. **Open a Link Once… (⌥⌘O)** explicitly bypasses rules and fallback and opens a chooser. The chooser can also propose a rule for your review; Open Once itself never creates one. Rules are stored locally, and tested links are not saved.

## Your apps and fallback

Open **Open With → Destinations & fallback → Manage…** for Web or Email. Pin your usual apps, then use a pin’s menu to move it up/down or unpin it. Other compatible apps stay available. Missing pinned apps remain listed until you remove the pin.

**When no rule matches** starts at **Show chooser**. Choose a fallback app only if you want unmatched links to open there automatically, then **Save Changes**. Rules take priority. If a rule or fallback app is unavailable, the chooser explains why. Web and email choices are independent; they do not change your Mac’s defaults. **Test a Link** includes fallback, and **Open a Link Once** bypasses both rules and fallback.

## Make CloakTools your link handler

In **Open With → Default link apps**, choose **Set Up…** for Web links or Email links. Review the current app, choose **Use CloakTools**, then respond to any macOS confirmation. Web setup covers HTTP and HTTPS; email setup covers mailto. They are independent. Nothing changes merely by opening the review.

Use **Restore…** to return to the previous available apps. If a previous app is missing or was not saved, select an installed alternative. Only link types still using this copy of CloakTools can change; choices made elsewhere are kept. A partial or declined change shows the actual current state and offers another review.

Restore your preferred defaults before uninstalling or deleting CloakTools’ settings. Ordinary browser navigation, embedded web views, explicit browser launches and Universal Links can bypass the router.

## What comes next

The first public beta includes Finder tools and web and email routing. Additional Finder folders and Shortcuts execution still require a provisioned build. See [Source](/source/) and [Support](/support/) for the current boundaries.

## Package a local preview

From the checkout, run `python3 scripts/release.py --preview`. This builds a Release app, verifies the app and extension signatures and versions, and creates a fresh ZIP with SHA-256 and manifest files under `apps/macos/build/Packages`. It is an ad-hoc local package, not a notarized installer. For manual replacement, quit the older copy first. Restore CloakTools web/mail defaults before removing the app.

The repository’s release guide documents a separate Developer ID/notarization path for later. No signing credentials or Team ID are included. Additional Finder folders and live Shortcuts execution remain gated until an appropriately signed build is available and tested.
