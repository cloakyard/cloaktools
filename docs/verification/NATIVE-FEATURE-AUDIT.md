# CloakTools native feature and usability audit

23 November 2026 · Development branch on Apple silicon, macOS 27.2.1 and Xcode 27.2.

All 31 Workbench entries were present across six categories with Developer Tools enabled. The fresh profile started with everyday tools. The audit visited all seven Settings tabs, checked the shared action layout and ran the native feature suites. The final build passed 248 core tests and 36 hosted tests. Individual workflows below identify where verification stopped at the model, handler or system boundary.

## Workflow coverage

| Workbench or system feature | Evidence from this audit |
| --- | --- |
| Create a new file, saved templates, saved file sets, create a folder with a file set, folder presets and language starters | Fixture suites exercised exact file contents, folder trees, Unicode and invalid names, collisions, concurrent publication, saved settings and Developer Tools visibility. A fresh app profile showed five everyday categories and added the sixth after enabling Developer Tools. |
| Reuse a folder structure, compare two folders and collect copies for sharing | Core fixtures checked selection, destination contents and changed inputs. Hosted checks exercised repeated Finder events, one collection across selections and saving selected branches. |
| File lists from Finder and the Workbench | Copy As and file-list fixtures checked output formats, escaping, selection limits and source changes. Hosted checks handed the Finder selection to the review. |
| Convert an image, Make an image fit, Optimize media files, Export video or audio | Reopened generated files and checked dimensions, limits or streams. The CLI produced HEVC with both encoders, VP9, AV1, animated GIF, MP3, Ogg Opus and FLAC. JPEG XL reconstructed the original JPEG byte for byte. Core tests covered GIF/WebP timing, native audio, cancellation and exact measured copies. |
| Combine files into a PDF and Organize PDF pages | PDF fixtures checked selected order, rotation, text, annotations, bounds and rejection of protected documents. Scan optimization tests checked a measured byte limit, ink position, retained invisible OCR, comparison input and an unattainable target. |
| Saved export recipes, folder rules, clipboard optimization, Drop Zone, menu bar, Recent Results and undo | Tested pipeline order, mixed inputs, folder migration, simultaneous watches, pause/resume, directory replacement and partial undo after reload. Named pasteboards exercised clipboard handling. A live GUI-saved pipeline produced a 187 × 125 WebP in the CLI. Filesystem and Mach-service access to Clop were denied for the isolated app run. |
| Clean up text, Combine text files into Markdown, Create a file from the clipboard | Text, digest and clipboard fixtures checked content, ordering, bounds, output naming and source preservation. Production clipboard contents were outside the audit. |
| Create a QR code and Read a QR code | Core fixtures encoded and decoded content types, handled multiple codes and invalid input. Hosted tests checked independent form drafts, field commits and whether a reviewed result could still be saved. |
| Open a link once, Test a link rule and Manage link rules and defaults | Tests checked preserved URLs, ordered matching, fallbacks, missing destinations, source attribution and default-handler recovery using test adapters. Inspected Links settings. Actual web and email defaults stayed with their existing providers. |
| Format or check JSON, Encode or decode Base64, Generate sample files and Create a configuration example | Fixture suites checked Unicode, malformed input, image payloads, size limits, example generation and retention of keys and structure. |
| Finder, Shortcuts, updates and distribution | Hosted tests exercised declared Finder Services, incoming Apple events and direct App Intent handlers. The public update check matched the live feed and archive size. The local website verification checked seven routes and 226 links/assets/anchors, and the Worker dry run passed. Website checks cover the public pages. |

The local Release preview passed archive checksum verification and strict code-signature verification after extraction. Its bundled CLI ran with Clop file access, Clop Mach-service lookups and outgoing Apple events blocked. The pipeline saved in the GUI converted a 14,873-byte PNG to a 1,772-byte WebP that decoded at 187 × 125 pixels. A 150 DPI PDF export reduced a 42,310-byte scan to 20,173 bytes under a 21 KB limit.

## Findings and fixes

| Observed behavior | Change and verification |
| --- | --- |
| Search returned zero results for “pipeline,” “compress scan,” “WebP” and “JPEG XL.” Folder rules required knowing their Settings location. | Added search terms and a direct automation settings entry. In the running app, “pipeline” and “watch folder” each produced one result. Command-Return opened the recipe library or the correct Settings section. |
| Pausing a configured folder rule required the menu bar item. | General now exposes Pause and Resume for configured automations. Both controls worked with the icon hidden in the test profile. |
| Choosing Standard in the Drop Zone could append files to an open recipe batch and use its settings. A removed recipe could silently fall back to Standard. | The Drop Zone honors its selected settings, preserves an incompatible open draft, and reports a missing recipe. A hosted test checks both reviews and their input selections. |
| A file already within its limit could leave the batch offering Preview Again. After a source edit the replacement error asked for a new preview, but the existing preview was ineligible. | Already-compact, within-limit and inapplicable pipeline rows can finish with Done. A row action reads the current file again. A regression test checks completion and verifies that refreshing reads the edited bytes. |
| Replacing a watched directory at the same path left its rule marked active while filesystem events still referred to the old directory. | The watcher checks the open directory identity against the path when scanning and before saving. An atomic directory swap now stops the rule. The test also checks that unrelated settings changes leave the stopped rule alone and an explicit retry starts monitoring again. |
| The Optimize Media File action could return a temporary system filename for an image supplied in memory. | The action uses the supplied filename and the encoded file extension. A direct invocation verified the name, decoded output and smaller byte count. |

## Simplicity and remaining checks

The first-run screen had one primary action. Advanced pipeline controls stayed in their editor. A live edit moved conversion ahead of resizing, and the saved summary displayed that order. The editor showed Cancel on the left and Save Pipeline on the right. A source review covered 36 uses of the shared footer. The hosted layout test measured dismissal, secondary and primary button positions at 400 and 660 points. The live walkthrough sampled workflows and Settings. It was an inspection by a contributor, without a first-time user study or spoken VoiceOver session.

The development build is ad-hoc signed. This Mac had no valid code-signing identity. Full Shortcuts invocation through macOS, signed cross-process access to additional Finder folders, notarization, and update installation over an existing user installation remain unverified. macOS 27.0, external shelf apps, Edge profile routing and a wider corpus of real-world media also remain open. The installed reference was Clop 3.7.6. Its outstanding feature differences, including recursive folder filters, watermarking and advanced pipeline branches, are tracked in the [Clop comparison](CLOP-PARITY.md).
