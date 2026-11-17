# File List verification

Verified 16 November 2026 in **0.5.6 (22)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **199 passing core tests**. The interface follows the preceding [UX audit](UX-AUDIT-TEXT-CLEANUP.md).

## Behavior

File List is an everyday tool in Finder Integration and the File menu. Select up to 200 local files/folders/links, review their order and choose CSV or Markdown. The Columns disclosure starts collapsed: Name is mandatory, Kind/Size enabled and Modified UTC/Full path disabled. A visible note identifies whether paths are exported. Metadata is captured without opening contents or enumerating folders; the final symbolic link is not followed. Sizes are regular-file bytes, with blank cells for folders and links.

Preview Export prepares immutable output. Items/Export share the workspace; Copy/Save uses the full prepared export regardless of the visible tab. Format, column, order or selection changes invalidate preparation; renaming retains the bytes. Refresh explicitly captures current metadata again. Failed additions/refreshes keep the prior selection and prepared output. Saving creates a new file with numbered collisions, then shows Show in Finder and Done. One Return dismisses the completed window.

CSV quotes every field, doubles quotes, uses CRLF record endings and prefixes formula-like cells with an apostrophe, with a visible protected-cell count. Markdown escapes punctuation and uses visible markers for embedded line breaks/tabs. Output is capped at 2 MiB; raw-text previews at 65,536 characters. Selected paths and metadata stay in memory only. See the [format contract](../FORMATS.md#file-lists) for exact transformations and [privacy policy](../../PRIVACY.md#file-lists).

## Automated verification

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **199 tests passed in 1.319 seconds.** Ten new tests cover immutable file/folder/broken-link captures, CSV commas/quotes/newlines/Unicode and formula-like cells, optional columns/UTC/order, Markdown markup/control escaping, invalid/missing/duplicate/special items, failed batches, selection/output/preview bounds, full safe publication with collisions and cancellation.
- Native Debug build passed. The existing App Intents metadata-skipped warning remains; no Swift compiler errors were reported.
- Astro reported zero errors/warnings/hints. All seven pages built and passed links/assets, canonical metadata, landmarks and pinned Air hash checks.
- Python's independent CSV reader parsed the live **527-byte CSV** into the expected header and four data rows. Quotes, formula protection, captured original size, UTC dates, full paths, blank folder/link sizes and CRLF record endings matched. No descendant names or file content appeared.
- The existing site dependency's independent Markdown parser parsed the live **187-byte Markdown** into a five-row, three-column table. Literal filenames, refreshed size, reordered rows and blank folder/link sizes matched. Full paths were absent.
- Existing preferences matched the earlier verification snapshot exactly after restoring New Files selection. The tool does not modify default web/mail handlers.

Logs: [core](file-list-core.txt), [native build](file-list-build.txt), [site](file-list-site.txt).

## Live native observations

1. Launched the new local build and opened File List from the first compact row in Finder Integration. The empty workspace offered Choose Items with the 200-item limit and metadata-only note.
2. Chose two synthetic files, a folder containing an unselected child, and a broken symbolic link in `/tmp/CloakTools-File-List-Verification/Items`. All four appeared with correct kinds, file sizes and blank folder/link sizes. The child was excluded.
3. Expanded Columns at the default window size. Both checkbox rows, the review pane and action footer remained usable after the disclosure animation. Enabled Modified UTC and Full path; the path note changed accordingly.
4. Previewed CSV: 527 bytes, quoted/doubled-quote filenames and one formula-like name prefixed with an apostrophe. Entering `bad/name` kept the preview but showed an inline error and disabled Save List. Restoring the name re-enabled saving.
5. Switched to Items before saving. The folder review stated the name, four items, 527 bytes and collision behavior. Save wrote `File list.csv` and returned the preview to Export.
6. Changed format to Markdown. The prior saved/result state cleared and Preview Export returned. Disabled date/path columns and collapsed the disclosure. After a synthetic source edit, Refresh updated its displayed size from 16 to 24 bytes. Move Up reordered the selected link before the folder. Preview produced 187 bytes.
7. Temporarily moved the synthetic note file, then refreshed from Items. A specific unavailable-file message appeared; all four captured rows and the prepared output remained available. Restored the synthetic file on disk. Save List still published the already-reviewed 187-byte Markdown and returned to Export with successful feedback.
8. One Return activated Done and returned to settings. Restored the original New Files category. No clipboard contents were read or replaced during this verification.

Screenshots: [item review](../../assets/screenshots/file-list-items-dark.png), [refresh recovery](../../assets/screenshots/file-list-error-dark.png), [saved Markdown](../../assets/screenshots/file-list-saved-dark.png).

## Website and boundaries

Updated Install, Support, Source and the shared Privacy content, plus the repository's README, format contract, architecture, design and roadmap. The Install guide was inspected in Chrome at 1728-pixel desktop width and 320 × 740 mobile size. Document width matched viewport width in both checks; text wrapped without horizontal overflow. No browser warnings/errors appeared. The temporary viewport override and tab were cleared, and the owned development server was stopped.

Screenshots: [desktop guide](../../assets/screenshots/file-list-guide-desktop.jpg), [mobile guide](../../assets/screenshots/file-list-guide-mobile.jpg).

This pass did not invoke Copy List, exercise the 200-item or 2 MiB limits interactively, or repeat all historical tool flows. Collision handling, bounds, cancellation and full output beyond the preview are covered in core tests. Exact minimum dimensions, Light appearance, increased contrast, full keyboard traversal and VoiceOver remain unverified for this new window. Cloud/network filesystems, broader lifecycle behavior and the existing signing/notarization/Finder scope release gates remain open. No public deployment or installer was produced.
