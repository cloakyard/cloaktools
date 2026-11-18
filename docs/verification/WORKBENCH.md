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
| Browse grouped tools | Finder Tools showed separate sections for creating files and working with a selection. At 800 pt wide, Files & Templates showed the three reusable starting points and wrapped the open image-fitting draft's name in the sidebar. |
| Search with the sidebar hidden | ⌘F revealed and focused the search field. “PDF” returned Combine, Organize and Create in that order. ⌘Return left those choices visible. “Merge PDF” returned one result and ⌘Return opened its review. |
| Return to search | ⌘[ restored the query and keyboard focus. Resume reopened the PDF draft. Cancel removed the draft and left the query available. Dismissing the link tester also returned to its originating search. |
| Search into an image picker | Cancelling Choose Image preserved “shrink photo”. Choosing the fixture opened its image-fitting editor. Back returned to the query with Resume available. |
| Recover from an empty result | A query with zero matches showed Clear Search. Activating it returned to the category. Light Finder and compact file views and dark search results were visually inspected. |
| Sidebar identity and search | The 44 pt icon and app name appeared above search in light and compact dark windows. ⌘F restored focus from a hidden sidebar, Escape cleared the query, and ⌘Return and ⌘[ opened a result and restored its search. |

The native build succeeded. All 224 core tests and 14 hosted tests passed. The hosted suite covers catalog visibility and ranking, search restoration across reviews and developer visibility changes, draft ownership, and the nesting and byte counts in a file-set review.

The scoped Finder extension was disabled on this Mac. Its contextual menu, spoken VoiceOver, and the full system accessibility-setting matrix remain live verification items. The Finder Services test above used Finder’s actual Services menu.

## Sidebar and Settings comparison

Inspected the installed CloakDrop 1.0.0 About window and ran its Debug sample catalog from a separate checkout to compare General, Rules, Privacy and About. The comparison covered the window, tab bar, control grouping, reading layout and external links.

| Surface | Observed in CloakTools |
| --- | --- |
| Sidebar | Accessibility geometry measured category rows at 32 pt before and 44 pt after. At 1000 × 700 pt in light appearance and 800 × 652 pt in dark appearance, all six categories and the Settings button were visible. The compact window also showed an open PDF draft. |
| Keyboard and entry points | ⌘F revealed a hidden sidebar and focused search. ⌘Return opened a PDF review, and ⌘[ restored its search. Finder Setup opened the Finder tab. Closing Settings and using the sidebar Settings button opened General. |
| Preferences | Opened all seven tabs with Developer Tools enabled in light and dark appearance. Both apps showed their Settings windows at 640 × 600 pt. General used grouped controls and section footers. Finder listed the four Services by their registered macOS names. |
| Privacy and About | Privacy showed a dated heading, a summary card and scrollable policy sections. About showed a centered icon, version and author above Updates. The accessibility tree exposed the website, repository, issue and support rows as links. |
