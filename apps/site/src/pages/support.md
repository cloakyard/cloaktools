---
layout: ../layouts/Reading.astro
title: Support
description: Practical help for the CloakTools development preview.
---
## A tool has moved

The 0.6.0 preview keeps existing tools in smaller groups. Expand **New Files → More text tools** for QR Code, Text Cleanup and Clipboard to File, or **Conversions → Image & PDF tools** for Convert Image, Assemble PDF and Organize PDF. Saved image defaults are under **Conversions → Image conversion defaults**.

The same actions are in **File → Text & Sharing** and **File → Images & PDFs**. Keyboard shortcuts still work directly. Saved templates, recipes, presets and Developer Tools choices are kept.

## Developer tools or saved items are hidden

Open **General → Your tools** and turn on **Developer Tools**. This reveals JSON, Base64, Sample Files and Example Copy, programming/JSON files, language settings, source-file examples and Shell arguments/JSON path list in Copy As. Everyday tools remain available either way.

Turning the group off hides technical templates and workflows without deleting them. Their favorites and language choices are kept. Known source/config extensions are classified using metadata only. Existing operations keep the choices they opened with; start a new operation to use the changed catalog. Missing template references remain available for repair.

Fresh installations start with the optional group Off and show a welcome choice once. Older installations retain it On.

## JSON or Base64 needs attention

Open the tool from **Developer Tools** or **File → Developer Tools**, paste text and explicitly run the action. JSON errors identify a line and column. Remove comments or trailing commas and use double-quoted keys/strings. Format and Minify preserve number precision and key order; Validate leaves the input unchanged.

For Base64, choose the alphabet that matches your input: Standard uses `+` and `/`; URL-safe uses `-` and `_`. Spaces, tabs, line breaks and missing padding are accepted. Invalid padding or characters are rejected. If decoded data is an image, switch to Image mode. Other binary files are not supported. Base64 is not encryption.

JSON and Base64 Text accept up to 1 MiB of UTF-8 input. JSON nesting is capped at 128 levels and formatted output at 8 MiB; try Minify or Validate if formatting expands too far. The result preview is limited to 65,536 characters, but Copy Result includes all output. Editing input/options clears old output, so run the action again before copying.

## Base64 image could not be decoded or saved

Choose **Base64 → Image** for PNG, JPEG, GIF, WebP, TIFF or HEIC/HEIF. Decode accepts standard Base64 (using `+` and `/`) or a data URL such as `data:image/png;base64,…`. If its declared type differs from the actual image, correct the prefix or paste just the Base64. SVG, arbitrary binary data and malformed images are rejected.

Images are capped at 10 MiB, 40 megapixels per frame and 512 frames; pasted Base64 at 14 MiB. The preview shows the first frame, while copying/saving keeps original bytes, metadata and animation. This is not a metadata-removal tool.

Decode does not write files. Review the preview and filename, then choose **Save Image…** and an existing writable folder. Collisions get a numbered copy. Editing the input clears the preview and save action; decode it again before saving.

## Sample Files needs attention

JSON and CSV need a whole-number record count from 1 to 10,000. Text and Binary need a whole-number size from 1 byte through 32 MiB. Use digits without commas or decimals, and check the selected unit: 1 KiB = 1,024 bytes; 1 MiB = 1,048,576 bytes.

Generate previews without writing. **Save File…** appears only after successful generation and needs a valid filename. Changing the format, count or size clears the old result; generate again. A shortened preview is expected for large files; saving and Copy Text include all content. Binary has no Copy Text action.

Choose an existing writable folder when saving. Existing names get a numbered copy. The fixed sample schema uses synthetic values and example email addresses; it does not read your files or contacts. Binary output is zero-filled, so it compresses unusually well.

## Example Copy needs attention

Choose a UTF-8 `.json`, `.env`, `.env.*` or `*.env` file up to 1 MiB. YAML, TOML, INI, CSV and binary formats are not supported. JSON errors identify a line and column; comments, trailing commas and malformed Unicode are rejected.

Environment files use single-line `NAME=value` assignments, optionally starting with `export`. Names use ASCII letters, digits and underscores, starting with a letter or underscore. A quoted value must close on the same line. Multiline values, continuations, mixed quoted/unquoted values and shell scripts are rejected with a line number. The error does not echo the value.

A failed replacement source clears the old preview and save action; choose a supported file to try again. Save Example writes a new visible `.json` or `.env` file; existing names receive numbered copies. Hidden output names are not supported. Copy/Save uses the full example regardless of the selected preview.

Keys, variable names and structure remain and can contain private information. Review them before sharing. This creates placeholders; it does not guarantee anonymization or a working configuration.

## A QR code needs attention

Use up to 1,024 bytes of plain text. Unicode can use several bytes per character. Whitespace-only text and binary controls are not accepted. If a code is too dense, choose 1024 or 2048 pixels, use Standard error correction or shorten the message, then create it again.

Keep the white border when placing the exported PNG in a document. Avoid stretching or cropping the code. High correction makes a denser image, and some readers may struggle with long messages. Check the intended scanner before sharing or printing; scanner display text can also hide a leading encoding marker.

Input or option edits clear the old preview so it cannot be saved accidentally. Filename edits keep the image; slashes, colons, control characters and hidden names are rejected. Save PNG writes the exact prepared image with a numbered filename if needed. Links are never opened automatically. Use the Read tab for codes in a selected image; camera capture is not offered.

## A QR code could not be read

Choose a single still PNG, JPEG, GIF, WebP, TIFF or HEIC/HEIF image, up to 10 MiB and 40 megapixels. A matching extension does not make invalid data readable. Export a frame from an animation or multi-page image first; PDF and SVG are unsupported.

If no code is found, use a sharper image with the whole code and its white border visible. Crop closer when a small code appears in a large picture; reading is limited to a 4096-pixel long edge. If there are more than 16 codes, crop to a smaller group. A code without readable text cannot be copied or saved. Decoded text is limited to 32 KiB per code.

For several codes, choose the matching number in the image or code menu before copying or saving. Choosing a new image clears the previous result; cancelling the file picker keeps it. A failed read never leaves the old text ready to export. Links stay plain text, and saving creates a numbered copy when the name already exists.

## Text Cleanup needs attention

Paste or type plain text up to 1 MiB, then choose **Preview Changes**. Binary controls are not supported. Only ordinary ASCII spaces and tabs are cleaned; nonbreaking spaces, zero-width characters and Unicode separators stay intact. Keep one applies to consecutive blank-line runs. Retained lines keep their existing CRLF, CR or LF endings.

Changing input or options clears the previous result. Preview again before copying or saving. A no-change result is valid; an empty result can be saved as a blank text file, with Copy disabled. Result previews stop at 65,536 characters, but Copy/Save includes all output. Input remains available for comparison.

Use a visible filename without slashes, colons or control characters and an existing writable destination. Existing filenames receive numbered copies. Cleanup can alter code indentation or Markdown trailing-space line breaks; review the result before using it.

## Markdown Digest needs attention

Choose regular UTF-8 text files, up to 32 files, 1 MiB each and 8 MiB combined. Folders, symbolic-link files, binary data and other text encodings are not supported. A failed addition leaves existing files intact. Repeated paths are skipped when other new files are also selected; a selection containing only included files asks you to choose another.

Use **Preview Digest** after changing the name, selection or order. File previews show captured content; to refresh an original edited elsewhere, remove and add it again. Long previews are shortened to 65,536 characters, while Copy/Save always uses the full digest. If output would exceed 12 MiB, remove files or choose smaller ones.

Save to an existing writable folder with a valid visible filename. Existing files receive numbered copies. The document preserves full source contents and filenames; it does not remove private information. Embedded Markdown and HTML are included as literal text, not rendered by CloakTools.

## Finder actions are missing

Check **Finder Integration → Manage Finder Extension** and open the scoped workspace from the app. Blank-space menus apply only inside that workspace. For a selected folder or image elsewhere, use Finder Services. Some cloud-provider and virtual views do not expose these menus.

## A file could not be created

Check that the selected destination still exists and is writable. Choose another folder if macOS denies access. Names cannot contain slashes, colons, control characters, or a leading dot. Existing files are never replaced; collisions receive a numbered suffix.

## A template could not be imported

Choose a UTF-8 text or source file up to 1 MiB. Binary files and null bytes are not supported. The library stores up to 64 templates and 16 MiB of content. Saved templates keep a copy, so later edits to the original do not change them. Use the template menu to edit its display title and default filename.

## A folder preset needs attention

Presets are saved starting points. **Use…** opens a review; it does not create a file immediately. A moved or unavailable folder can be corrected with **Change…** in the review or by editing the preset. There is no automatic bookmark tracking. If a saved template was removed, choose another in the preset editor. Presets never enable Hello World while the global or language setting is Off; saved custom content is independent. Removing a preset does not remove files or its destination folder.

## A file set needs attention

Each file or folder needs a unique relative path inside the new folder. Use `/` for subfolders; avoid hidden names, `..`, empty path segments, colons and backslashes. Letter-case or Unicode-equivalent duplicates are rejected, and a file cannot also be a parent folder. The file extension must match the selected type. Choose another type if an imported template was removed.

Review prepares exact contents; Create Folder publishes the complete folder. If the destination is unavailable, use Change and retry. Existing folders are never merged: collisions receive a numbered name. Cancellation before publication removes unfinished staging; a completed publication remains successful. An abrupt app termination can leave a hidden staging folder. Save Set stores the structure only, and does not create output.

## Clipboard content could not be read

Copy one text selection or one image’s contents, then invoke **New File from Clipboard…** again. Copying a file icon in Finder is not the same as copying image contents from Preview. Text is limited to 1 MiB; images to 100 MB and 40 megapixels. PNG, JPEG and TIFF clipboard images are supported; rich-text-only data, copied files and multiple items are not. If access is denied, review CloakTools’ clipboard access in System Settings. The app never changes that permission automatically.

## An image could not be converted

Choose a single-frame PNG, JPEG, TIFF or HEIC image up to 40 megapixels and 100 MB. Try opening the source in Preview. A misleading filename does not make invalid contents supported. Output can be PNG, JPEG or HEIC; unavailable native encoders are disabled. The original remains unchanged.

PNG preserves transparency. JPEG and HEIC use the selected white or black background; quality changes compression, not dimensions or a guaranteed file size. Output is standard 8-bit sRGB. HDR, depth and original camera/location metadata are not preserved. Multiple frames/pages, animation and RAW are not supported.

## An image cannot meet the size limit

Make It Fit shows the measured result and prevents saving when it exceeds your limit. Increase the maximum KB, choose a different format, or lower the quality floor for JPEG/HEIC. Allow further reduction if smaller dimensions are acceptable. PNG preserves transparency, so its size changes through dimensions rather than a quality slider.

Further reduction stops at a 320 px long edge, or the smaller starting size after Fit within. Images never enlarge. The search is bounded and does not promise the largest theoretically possible result. Acceptable fields are 1–100,000 KB and 1–20,000 px; 1 KB means 1,000 bytes. Edit a limit, then use Preview Fit again. Cancellation waits for any active native encoding step to finish; no preview file is saved.

## A PDF could not be assembled

Choose up to 32 PDFs/images, 200 pages, 100 MB per file and 200 MB total. Images are also limited to 40 megapixels. Encrypted PDFs, restricted documents, forms and signatures are unsupported. Page text, sizes and annotations are retained; document bookmarks and other document-level structures are not merged. Internal navigation links are not guaranteed. A failed addition leaves the prior selection intact.

## PDF pages do not match the intended selection

**Organize PDF** labels pages with their original numbers even after reordering. Checkboxes control export inclusion; clicking a row focuses its preview and rotation controls. A range such as `1, 3–5` changes inclusion when you press Apply; it keeps your current order and rotations. Invalid ranges leave the selection intact. Reset restores all original pages and rotations.

Export Copy is disabled when no pages are included. Choose one ordinary PDF with up to 200 pages and 100 MB. Encrypted/restricted PDFs, forms and signatures are unsupported. Page text and ordinary annotations are retained, but bookmarks, page labels and internal navigation are not rebuilt. Excluding pages is not a redaction or metadata-sanitization feature. Native rendering may finish its current step before cancellation takes effect.

## A media export is unavailable or failed

Choose one self-contained MOV/MP4/M4V movie or M4A/MP3/WAV/AIFF/CAF audio file. CloakTools checks actual tracks and native preset compatibility; a familiar extension does not guarantee support. MP4 choices require a video track; M4A requires audio. Supported inputs are H.264/SDR HEVC video and AAC/MP3/PCM audio, with limits of 1 GB, 30 minutes, video up to 4096 × 2160 at 60 fps and mono/stereo audio up to 96 kHz.

HDR/wide-gamut, alpha, spatial media, protected files and multiple video/audio tracks are unsupported. Exports omit chapters, subtitles and source metadata. Native presets choose compression, so a copy is not guaranteed to be smaller. Audio padding can make a container's reported duration slightly longer than playback.

Keep enough free disk space for the private input copy and output staging. Cancel waits for native work to stop and removes unfinished staging. Closing the operation removes its private capture during normal use; an abrupt app exit can leave temporary files. A completed copy remains saved even if cancellation arrives after publication. The original stays unchanged.

## An export recipe needs attention

**Use…** asks for a fresh source and opens a review. It does not export immediately. Make It Fit always needs a new preview; a saved limit cannot guarantee that another image will fit. A media recipe that is incompatible with the source keeps its requested preset visible and disables Export Copy. Choose an available format in **Export as**, or cancel and select another source.

Recipes save output settings only. Choose the source, destination and filename again for each export. Editing a draft leaves the saved recipe unchanged until **Save Changes**. **Save as a new recipe** preserves the original. If the recipe changed or was removed while its dialog was open, reopen the current version or save a new copy.

Names accept 1–80 characters without control characters; up to 32 recipes can be saved. An unreadable or newer-format library is kept intact. Restore a known-good local `export-recipes.json` or use a compatible app version, then **Reload Recipes** in Conversions. Removing a recipe does not remove source or exported files.

## File List needs attention

Choose up to 200 local files, folders or symbolic links. If an item moved or is unavailable, a failed addition or Refresh keeps your existing list. Remove the affected item or choose it again. Captured details do not update automatically; Refresh reads them again and requires a new preview.

Folder and symbolic-link sizes are blank because File List does not scan descendants or follow link targets. CSV uses quoted cells and may prefix formula-like names with an apostrophe for spreadsheets. Markdown escapes punctuation and displays embedded line breaks/tabs as symbols. Full paths are optional and start off. Review the Export tab before sharing.

Use a visible filename without slashes, colons or control characters. Save List writes the complete prepared export even if Items is visible; existing names receive numbered copies. If the 2 MiB output limit is reached, reduce the selection or turn off full paths.

## A copied list looks different

Select the format that suits where you will paste. Plain names and paths use line breaks between items; JSON is unambiguous when a filename itself contains a line break. Shell arguments are quoted for sh, bash and zsh and include no command. Copy As accepts up to 200 items and 1 MiB of output. Its preview shows at most 8,192 characters; Copy includes the full text. Local file links still depend on the receiving application and access to the original path.

## A destination app is missing

The chooser lists apps macOS reports as compatible with the incoming link. Install or restore a compatible application and refresh. Microsoft Edge is supported as an application when installed and registered; specific profiles are not offered in this preview. Choosing an email app does not select its From account.

## A rule did not open the expected app

Use **Test a Link** to inspect the first matching rule and its destination. Check rule order, enabled state, Web/Email role, and Match All versus Any. Host matching uses domain boundaries; `company.example.attacker.test` does not match `company.example`. Subdomains require their own condition choice. Path matching is a case-sensitive encoded prefix; `%2F` differs from `/`.

An unavailable destination uses the chooser and does not continue to a later rule. The source is normally Unknown; the tester’s source field is only a simulation. To-recipient rules inspect plain To addresses, including the `to` field, and ignore cc, bcc, subject and body. Quoted/display-name addresses are not matched by recipient conditions.

Rules apply only to links delivered to CloakTools. Browser-internal navigation, embedded views, explicit browser launches and Universal Links can bypass it. **Open a Link Once** deliberately bypasses rules and fallback. If the rules file cannot be read, incoming links use the chooser; restore a known-good local rules file and use Refresh Status. No system default changes are performed on launch.

## A fallback or pinned app is unavailable

Open **Destinations & fallback → Manage…** for the link type and choose **Refresh**. The list shows installed compatible apps and supported schemes. Missing pins remain until unpinned; a missing fallback uses the chooser. Select another app or **Show chooser**, then **Save Changes**. Pins change order only and never automatically open links.

Use **Test a Link** to distinguish a matched rule from a fallback. A matched rule with a missing destination does not continue to the fallback. **Open a Link Once** bypasses both. If destination settings cannot be read, automatic routing stops; restore a known-good local `routing-destinations.json` and use Refresh Status. Cancelling the manager discards its edits.

## A default-app change did not complete

Open **Default link apps** in Open With and use **Refresh Status**. macOS may require a confirmation prompt for a browser change. If you decline or a change fails, CloakTools stops further requests and shows the actual current apps. HTTP and HTTPS may differ; the web review handles them separately. Use Review Again to inspect the new state before retrying.

**Restore…** changes only link types still handled by this copy of CloakTools. Defaults changed outside the app are kept. Missing prior apps require an explicit alternative. Setup and restoration are separate from rule editing; neither action creates a routing rule. macOS does not provide an atomic multi-scheme change, so avoid changing defaults in another app while a consent prompt is pending.

If the recovery record cannot be read, restore a known-good local copy of `default-handlers.json`, or change defaults through your preferred browser/mail app. Restore defaults before uninstalling CloakTools or deleting its settings.

## An operation was cancelled

Cancellation is normal feedback. While the app shows **Stopping…**, native work is finishing its current step. You can close the operation after it stops. If publication already completed, the saved copy remains and the app reports success. Destination paths and status stay beside the action controls; use **Change…** to recover from a wrong or unavailable folder without starting over.

## Report a problem

Include the app version, macOS version, entry point, expected result, actual result, and steps using synthetic files or example links. Remove personal paths, full URLs, tokens, email recipients, and message bodies from any screenshots or logs.

Use [GitHub issues](https://github.com/cloakyard/cloaktools/issues) for reproducible problems. The repository includes [contribution guidance](https://github.com/cloakyard/cloaktools/blob/main/CONTRIBUTING.md), [security reporting](https://github.com/cloakyard/cloaktools/blob/main/SECURITY.md), and verification notes. [Source and release status](/source/) explains what is available.

## Shortcuts in the local preview

Make Image Fit, Make Markdown Digest and Review Saved File Set are implemented and can appear in the Shortcuts library. On the tested Mac, an ad-hoc build cannot execute them because macOS cannot establish its team signing identity. General explains the limitation. Use the matching native tools for now; a signed build still needs end-to-end verification. A Shortcuts action does not create a file set automatically.

Additional Finder folders have the same signed-build boundary. The workspace and selected-item Services remain the supported local-preview paths. Signing and notarization are deferred; no paid account is needed to build and use the ordinary local tools.
