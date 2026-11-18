# Native Workbench verification

Checked the ad-hoc Debug build on Apple silicon with macOS 27.2.1 and Xcode 27.2. The file workflows used temporary local fixtures.

| Interaction | Observed result |
| --- | --- |
| Open the app and choose Finder Setup | The Workbench showed Finder Tools. Finder Setup opened a second window with the Finder tab selected. |
| Close Settings and press ⌘, | General opened in the separate Settings window. With only Settings visible, reopening the app through Launch Services brought the Workbench to the front. |
| Find a tool | ⌘F focused search, including when only Settings was open. Typing “shrink photo” returned the image-fitting action. |
| Start PDF assembly from Finder | Finder → Services → Assemble PDF with CloakTools opened both selected PDFs for review. After reordering and creating the output, PDFKit read the two pages back in the chosen order. |
| Leave and resume a PDF review | Back preserved the reordered image inputs. Resuming and creating the PDF produced a two-page document. |
| Fit an image | ⌥⌘K opened the source picker. Preview Fit measured a 17,287-byte JPEG. Save JPEG Copy wrote exactly 17,287 bytes beside the fixture. |
| Create a file set | ⇧⌘N opened the destination picker. Review showed the Notes starter tree. Create Folder produced README.md, notes/Notes.md and the empty assets folder. |
| Check JSON in dark appearance | Validate reported the line and column of a trailing comma. Correcting the input and pressing ⌘Return produced “Valid JSON”. |
| Test a link rule | ⌥⌘T opened the link tester. |

The native build succeeded. All 224 core tests and 11 hosted tests passed. The hosted suite covers catalog visibility and matching, draft ownership, and the nesting and byte counts in a file-set review.

The scoped Finder extension was disabled on this Mac. Its contextual menu, spoken VoiceOver, and the full system accessibility-setting matrix remain live verification items. The Finder Services test above used Finder’s actual Services menu.
