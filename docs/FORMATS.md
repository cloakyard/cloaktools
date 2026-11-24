# File format capabilities

All built-in text/source templates are UTF-8. Plain Text and Markdown stay empty. Programming files use the master + retained language choice; global Off always wins. No code is run and no language runtime is installed.

Everyday mode exposes plain text, Markdown and PDF. Enable **General → Developer Tools** for JSON and all programming types below, plus the standalone JSON, Base64, Sample Files and Example Copy tools described at the end of this page. The group changes visibility; the blank/starter rules remain unchanged.

| Type | Extension | Hello World form |
| --- | --- | --- |
| Plain Text | txt | Blank |
| Markdown | md | Blank |
| JSON | json | Valid empty object `{}` plus newline, independent of Hello World |
| PDF | pdf | Valid one-page blank A4 document, independent of Hello World |
| Python | py | `print` |
| JavaScript | js | `console.log` |
| TypeScript | ts | `console.log` |
| Swift | swift | `print` |
| Rust | rs | `fn main` + `println!` |
| C | c | `int main(void)` + `puts` |
| C++ | cpp | `int main` + `std::cout` |
| C# | cs | Modern C# top-level `Console.WriteLine` |
| Java | java | Nonpublic `HelloWorld` class + `public static void main` |
| Go | go | `package main` + `fmt.Println` |
| Ruby | rb | `puts` |
| PHP | php | PHP opening tag + `echo` |
| Kotlin | kt | `fun main` + `println` |

The Java class is deliberately nonpublic so a user-selected filename remains valid. C# uses top-level statements (C# 9+). These are common languages, not a claimed popularity ranking. User environments/compiler versions determine how to run them outside CloakTools. Tests cover byte content, extension, file publication and settings for every language; generated programs are not executed.

PDF uses Core Graphics, is decoded in tests with `CGPDFDocument`, and has a single 595.276 × 841.89 pt A4 page. JSON is validated with `JSONSerialization`. These are format-aware blank documents, never zero-byte placeholders. Archives and Office files remain deferred.

Imported templates accept regular UTF-8 text/source files (including CRLF), without null bytes, up to 1 MiB; their alphanumeric extensions may contain up to 16 bytes. Exact bytes are copied and preserved, including an empty file. Saved content always takes precedence over optional Hello World. Imported text with a structured extension is not parsed or promised to be valid in that format. Binary and image templates are not offered. Related file sets and reusable folder templates are available through their separate reviewed workflow. Known programming/config extensions in imported templates are shown only with Developer Tools enabled; turning it off retains the stored bytes.

Clipboard creation accepts one plain-text representation (UTF-8, up to 1 MiB, no null characters), or one single-frame PNG/JPEG/TIFF representation (up to 100 MB / 40 megapixels). Text becomes `.txt`; image data is decoded, orientation-applied and re-encoded as `.png`, preserving transparency and excluding original camera/location metadata. Full-resolution output is separate from the 384-pixel preview thumbnail. RTF/HTML-only data, copied file URLs/promises, multiple clipboard items, GIF/animation and PDF clipboard data are unsupported.

The library supports 64 items and 16 MiB total content; disk reads are bounded even if a source grows during import. Open After Creation uses TextEdit for imported/text/source documents and Preview for built-in PDFs. No extension association can cause generated source code to execute.

## Native image conversion

| Input | PNG output | JPEG output | HEIC output |
| --- | --- | --- | --- |
| PNG | Yes, alpha preserved | Yes, flattened | Yes, flattened |
| JPEG | Yes | Yes | Yes |
| TIFF, one page | Yes, alpha preserved | Yes, flattened | Yes, flattened |
| HEIC/HEIF, one image | Yes, alpha if present | Yes, flattened | Yes, flattened |

Inputs are identified by ImageIO content, not trusted extensions. Limits are 100 MB encoded and 40 megapixels, checked before full decoding. Multi-frame images, multi-page TIFF, animations and unsupported types are rejected. Native output capability is checked on the current Mac; unavailable encoders are disabled. All twelve matrix directions were encoded and decoded on the verification host.

Preparation reads bounded source bytes on a worker, applies orientation and captures fully decoded pixels in memory. The thumbnail and eventual output use that same capture; source changes after preview cannot alter the result. No output is written until Convert. Originals are never overwritten, including same-format conversions; collisions get numbered names.

All outputs are standard **8-bit sRGB/SDR**. PNG uses lossless compression of those normalized pixels and preserves alpha; this does not promise lossless preservation of an input’s original color space or higher bit depth. JPEG and HEIC use 10–100% native quality and explicitly composite transparency onto white or black. The slider controls compression, not a byte-size target or dimensions. HDR/gain maps, depth and original camera/location metadata are not retained.

Defaults are PNG, 90% quality and white background. Quality/background choices remain stored while PNG is selected and apply when choosing a lossy format. Each operation captures preferences independently. Return converts, Escape cancels, and a completed copy can be opened explicitly in Preview.

## Make It Fit

Accepts the same single-frame image inputs and PNG/JPEG/HEIC native encoders above. The per-operation defaults are JPEG, 500,000 maximum bytes, a 1600 × 1600 px bounding box, 60% minimum encoding quality, white background and further reduction allowed. Bounds are 1,000–100,000,000 bytes and 1–20,000 px per dimension. KB and MB use decimal units. A bare number in the Workbench means KB. “Under 2 MB” sets an exact maximum of 1,999,999 bytes, including when saved in an export recipe.

Images never enlarge and fit the bounding box with pixel rounding. Optional additional reduction stops at a 320 px long edge, or the smaller initial bounded size. JPEG/HEIC flatten transparency and try compression before dimensions; PNG retains alpha and compresses losslessly after normalization/resizing. The quality value is a native encoder setting, not a perceptual-quality guarantee.

Preview measures actual bytes, shows actual dimensions and decodes its thumbnail from the encoded output. The bounded search does not promise the mathematically largest possible resolution or highest possible quality. An over-budget result cannot be published. Save uses exactly the previewed bytes with no source reread, recompression or overwrite. Normal metadata/color-depth limitations apply.

## PDF assembly

Combine ordinary PDFs and any supported single-frame image input. Each image becomes one orientation-applied, centered A4 page, portrait or landscape, with white background and 24-point margins. Existing PDF pages preserve media/crop boxes, rotation, text and annotations. Whole files are reordered; pages within each source keep their sequence. Document bookmarks and other document-level structures are not merged, and internal navigation links are not guaranteed. Encrypted/restricted PDFs and PDFs with AcroForm/widgets or document-signature permissions are rejected, rather than modifying those structures. No OCR is performed.

Limits: 32 files, 200 pages, 100 MB per source, 200 MB total source bytes, 200 MB prepared PDF bytes and 200 MB output. Images retain the 40-megapixel input cap. Source changes after preparation cannot change the output. Captured PDFs remain local and are not treated as metadata-sanitized copies.

## PDF page organization

Accepts one ordinary PDF with 1–200 pages and up to 100 MB. Include pages individually or by original one-based ranges, reorder them, and apply relative 90-degree rotations. Each original page can appear at most once; duplicate-page creation and combining additional sources belong to other workflows. Export preserves page text, media/crop boxes and ordinary annotations, then writes a separate PDF up to 200 MB.

The same encryption, assembly-permission, form/widget and signature exclusions as assembly apply. Bookmarks, page labels and document-level structures are not rebuilt; internal links are not guaranteed after removing/reordering pages. No OCR, content redaction or metadata scrubbing is provided. Omission removes a page from the page tree; it is not a forensic data-removal guarantee. Thumbnails use 192-pixel bounds with a 32 MB encoded total cap; one focused 768-pixel preview is rendered on demand. Source bytes are captured once and never reread for export.

## Focused media export

One self-contained local file, up to 1 GB / 30 minutes. File-panel extensions: MOV, MP4, M4V, M4A, MP3, WAV, AIF/AIFF and CAF. Container extensions alone do not establish support; AVFoundation inspects tracks and preset compatibility. One H.264/HEVC SDR video track and at most one audio track, or one audio-only track. Audio codecs: AAC, MP3 or linear PCM, mono/stereo, up to 96 kHz. Video fits a 4096 × 2160 bounding box (either orientation), up to 60 fps. HDR, wide gamut, alpha, spatial media, protected media and multiple video/audio tracks are rejected.

| Verified synthetic input | MP4 up to 720p | MP4 up to 1080p | M4A audio |
| --- | --- | --- | --- |
| MOV · H.264 + PCM audio | H.264 + AAC | H.264 + AAC | AAC |
| MOV · H.264 silent/rotated | H.264, silent | H.264, silent | Not offered |
| MOV · SDR HEVC portrait | H.264, silent | H.264, silent | Not offered |
| MP4 · H.264 + AAC | H.264 + AAC | H.264 + AAC | AAC |
| M4A · AAC | Not offered | Not offered | AAC |
| MP3 | Not offered | Not offered | AAC |
| WAV / AIFF / CAF · PCM | Not offered | Not offered | AAC |

M4V is accepted for inspection but was not separately verified as a container in this slice. Capability checks can reject individual files even within a listed category. Video presets preserve proportions, preferred orientation and smaller source dimensions; a 1920 × 1080 fixture was decoded at 1280 × 720 after export. M4A extracts audio without video. Native presets choose bitrate and frame-rate behavior; there is no byte target or frame-exact trimming. AAC priming/padding can produce slightly different container versus playback duration (the 12-second fixture showed 12.053 seconds in ffprobe and 12 seconds in AVFoundation/QuickTime).

Exports include the full selected media tracks with their timeline offsets. Chapters, subtitle/timed-metadata tracks and source metadata are omitted. Visible/audible content is retained. Output is validated before publication and capped at 2 GB after encoding, not during every native write. Originals are captured in private temporary files and never overwritten. Cancellation removes staging; crashes may leave temporary capture/staging files. Disk capacity, complex files and full upper-bound workloads need broader validation.

### Subtitle files in development builds

Generate Subtitles accepts the media inputs above with one audio track. Each selected language produces a separate UTF-8 SubRip (.srt) file with numbered captions and millisecond start and end times. A language tag precedes the extension. All tracks share the source timeline. Apple Speech supplies the times, and Apple Translation handles supported pairs locally.

## Copy As text formats

Full paths, names and file URLs use one item per line; shell arguments use single-quoted POSIX arguments separated by spaces; Markdown uses escaped labels and angle-bracketed, encoded file URLs; JSON uses an array of absolute paths. File names and paths with embedded line breaks are preserved in plain text but can be ambiguous there; use JSON for a reversible list. The formatter never reads files, resolves symbolic links or executes a shell. Limits: 200 items, path lengths under 4,096 UTF-8 bytes, output up to 1 MiB; previews show up to 8,192 characters.


## Developer text tools

These are local text workspaces, separate from file creation and conversion. Enable Developer Tools, then open JSON or Base64 in its sidebar category or the File menu.

| Tool | Input and output | Limits |
| --- | --- | --- |
| JSON | Format with two-space indentation, Minify, or Validate; preserves number tokens, key order, duplicates and string escapes | 1 MiB UTF-8 input, 128 container levels, 8 MiB formatted output |
| Base64 Text | UTF-8 text ↔ standard or URL-safe Base64; URL-safe encoding omits padding; decoding accepts ASCII whitespace and missing padding | 1 MiB UTF-8 input; non-text output directs images to Image mode |
| Base64 Image | PNG/JPEG/GIF/WebP/TIFF/HEIC/HEIF ↔ standard Base64 or image data URL; exact bytes and metadata retained | 10 MiB images, 14 MiB pasted Base64, 40 megapixels per frame, 512 frames |

JSON rejects comments, trailing commas, invalid escapes and unpaired escaped surrogates. Base64 rejects mixed alphabets, invalid padding and non-zero pad bits. Previews show at most 65,536 characters; Copy Result includes the complete output. Input stays intact, and editing invalidates prior output. Text is not saved or transmitted. Image decoding previews the first frame; Save Image explicitly writes the original bytes as a new numbered copy. Invalid MIME declarations, SVG and non-images are rejected. See [image verification](verification/BASE64-IMAGES.md) and [text verification](verification/DEVELOPER-TEXT.md).


## Sample files

Enable Developer Tools, then open Sample Files in its sidebar category or File menu. Generate previews content in memory; Save File writes exact prepared bytes using numbered collision handling. The same settings produce identical content. No source files are read.

| Format | Contents | Bounds |
| --- | --- | --- |
| JSON | Pretty-printed UTF-8 array, sorted keys, trailing newline; deterministic ID/name/example email/boolean/note fields | 1–10,000 records |
| CSV | Same records, UTF-8 header, escaped quotes and quoted delimiters/line breaks, CRLF record endings | 1–10,000 records |
| Text | Repeated ASCII line, truncated to the exact requested byte count | 1 byte–32 MiB |
| Binary | Zero-filled `.bin`; useful for size-limit testing, not realistic compression ratios | 1 byte–32 MiB |

Size units are Bytes, KiB (1,024 bytes) and MiB (1,048,576 bytes); entries must be whole numbers. Text previews are bounded to 8,192 bytes at a valid UTF-8 boundary. Binary shows the first 64 bytes as hex. Copy Text includes all JSON/CSV/text content. Record notes cycle through ordinary text, commas, quotes, multiline text and Unicode. The schema is fixed; random seeds, custom columns, configuration imports and generated image/media fixtures are outside this slice. See [Sample Files verification](verification/SAMPLE-FILES.md).


## Example copies

| Input | Example behavior |
| --- | --- |
| `.json` | Strict JSON; keys/order/duplicates and containers kept, strings → `"REPLACE_ME"`, numbers → `0`, booleans → `false`, null unchanged |
| `.env`, `.env.*`, `*.env` | Single-line ASCII `NAME=value` assignments, optional export; values → `REPLACE_ME`, comments/blank lines removed, LF output |

Input is UTF-8 up to 1 MiB; a leading UTF-8 BOM is accepted and omitted from previews/output. JSON depth/output limits are 128 levels/8 MiB. Environment quoted values must close on the same line, followed only by whitespace or a comment; mixed unquoted/quoted values and continuations are rejected. Variable names use ASCII letters, digits and underscores, starting with a letter or underscore. No shell expansion/execution or YAML/TOML/INI/CSV parsing is offered.

Both read-only previews are bounded to 65,536 characters; full example content is saved/copied. Original keys/names/structure remain, so review is needed before sharing. Output is a new `.json` or visible `.env` file with safe numbered collisions. See [Example Copy verification](verification/EXAMPLE-COPY.md).

## Markdown digests

Everyday tools include Markdown Digest in New Files and the File menu. Choose 1–32 regular local UTF-8 text files of any extension, at most 1 MiB each and 8 MiB total. Folders, direct symbolic links, duplicate standardized paths, malformed UTF-8 and binary control characters (C0 except tab/CR/LF, plus DEL) are rejected. Empty text files are supported. Adding an invalid batch leaves the prior selection intact; already-included paths are skipped when a batch also includes new files.

Output is a UTF-8 `.md` document, capped at 12 MiB, with numbered filename-only headings and literal fenced source blocks. Heading punctuation is escaped; heading controls are replaced with spaces. Source contents preserve Unicode, BOMs and line endings; framing adds a newline before the closing fence when needed. A fixed extension map adds language hints, falling back to `text`; syntax is not validated or executed. Fences accommodate embedded Markdown without turning it into document structure.

The read-only previews show up to 65,536 characters each; Copy/Save includes the complete digest. Captures are immutable, so later original edits require removing and adding that file again. Existing output names receive numbered copies. See [Markdown Digest verification](verification/MARKDOWN-DIGEST.md).

## Text cleanup

Everyday Text Cleanup accepts typed/pasted text up to 1 MiB of UTF-8. C0 controls other than tab/CR/LF, and DEL, are rejected. It optionally trims ASCII spaces/tabs from line starts/ends, collapses each run to one ordinary space, and keeps all blank lines, keeps the first in each run, or removes them. A blank line contains only ASCII spaces/tabs. Only trimming line ends is enabled by default.

CRLF, CR and LF terminators on retained lines are copied exactly. No final newline is added; removing a terminal blank line removes its terminator. Unicode, BOMs, nonbreaking spaces, zero-width characters and Unicode line separators are left intact. EOF immediately after a terminator is not another logical line. Changed-line counts include removed lines. Cleanup can change indentation or Markdown trailing-space semantics; compare before using the result.

Output cannot exceed the input byte length. The result preview contains at most 65,536 characters, and full output is copied or saved as a numbered UTF-8 `.txt` copy. Empty output is saveable with Copy disabled. See [verification](verification/TEXT-CLEANUP.md).


## File lists

Everyday File List accepts 1–200 explicitly selected local files, folders or symbolic links. It captures metadata using `lstat`, without opening contents, scanning descendants or following the final link. Devices and pipes are rejected. Selected paths must be absolute and under 4,096 UTF-8 bytes; duplicate standardized paths are rejected. Failed additions/refreshes keep the prior captures. Order is explicit and metadata stays fixed until Refresh.

Name is always included. Kind and Size (bytes) start enabled; Modified (UTC) and Full path start disabled. Sizes are logical regular-file byte counts, with blank cells for folders/links. Dates use ISO 8601 UTC at whole-second precision. CSV quotes every field, doubles embedded quotes, keeps embedded line endings inside quoted cells and uses CRLF record endings. A cell whose first significant character is `=`, `+`, `-` or `@` receives a leading apostrophe (ignoring whitespace, controls and BOM for detection); a visible count identifies these spreadsheet safeguards. This intentionally changes those cell strings.

Markdown uses a pipe table, escapes ASCII punctuation, converts embedded line breaks and tabs to visible `↵`/`⇥` markers and replaces other controls with `�`. These markers are display representations, not a reversible filename encoding. Names and paths are literal text, not clickable Markdown links or raw HTML.

Output is UTF-8, capped at 2 MiB; the raw-text preview shows up to 65,536 characters. Copy and Save use the complete prepared output. Safe publication creates `.csv` or `.md` files with numbered collisions, without changing originals. See [File List verification](verification/FILE-LIST.md).


## QR creation

Create QR Code accepts up to 1,024 UTF-8 bytes after formatting. Text mode preserves whitespace, line endings and Unicode representation. It rejects blank input, DEL and C0 controls other than tab, CR and LF. Web link accepts HTTP and HTTPS addresses. Email uses a percent-encoded mailto URI, Phone call and Text message use international numbers in tel and sms URIs, and Map location uses a geo URI with decimal latitude and longitude.

Contact cards encode vCard 3.0. Calendar events encode iCalendar 2.0 with UTC start and end times. Both use CRLF and fold long lines on UTF-8 scalar boundaries. Wi-Fi uses the WIFI format with escaped delimiters, a hidden-network flag when requested, and a password only for protected networks. [vCard](https://www.rfc-editor.org/rfc/rfc2426) · [iCalendar](https://www.rfc-editor.org/rfc/rfc5545) · [Wi-Fi QR convention](https://github.com/zxing/zxing/wiki/Barcode-Contents#wi-fi-network-config-android-ios-11)

Output is an opaque black/white sRGB PNG at exactly 512, 1024 or 2048 pixels per side. Standard uses QR correction M; High uses H. Native Core Image generates the module matrix. Integer scaling avoids blended edges, requires at least four pixels per source module and leaves at least four white modules of additional border on every side. Dense payloads may require 1024 or 2048 pixels. If the selected size cannot satisfy the module minimum, generation returns a recoverable error without output.

Shorter text generally scans more easily. High correction increases density; it does not guarantee compatibility with every reader. Core Image's QR detector decoded the 1,024-byte High fixture in tests, while Vision did not detect that dense code on this host. Test with the intended scanner before sharing or printing; physical reader coverage remains open. The app shows a density hint for prepared inputs above 512 bytes.

Copy Image and Save PNG use the full prepared PNG without re-encoding or truncation. No transparent, colored, SVG, PDF or logo-embedded QR output is offered. Saved names receive collision protection. The same workspace also reads codes from selected still images, as described below. See [QR verification](verification/QR-CREATION.md).

## QR reading

Read accepts actual PNG, JPEG, GIF, WebP, TIFF and HEIC/HEIF content from one explicitly selected regular local file. Limits are 10 MiB, 40 megapixels and one frame. Animation, multi-page images, PDF and SVG are rejected. ImageIO applies orientation and limits scan pixels to a 4096-pixel long edge; the displayed PNG preview is at most 768 pixels. Large images show a closer-crop hint because small codes can be lost during reduction.

Vision and Core Image QR detectors supply spatially merged results, with up to 16 codes and 32 KiB of decoded UTF-8 per code. Duplicate payloads in different locations remain separate numbered codes. A valid image with no detected code returns its preview and a recovery hint. A detected code without readable text remains selectable with copying/saving unavailable; empty text is saveable with Copy disabled.

Copy Text and Save Text preserve the entire decoded string with no added newline. A complete vCard or VCALENDAR wrapper also enables export as `.vcf` or `.ics`. All three formats use numbered collision protection. Scanner interpretation may omit a leading BOM or interpret an encoded character set. Raw QR codewords/binary payload extraction is not offered. Poor focus, small codes, distortion, dense payloads and native detector differences can prevent detection; universal scanner coverage is not claimed. See [QR reading verification](verification/QR-READING.md).
