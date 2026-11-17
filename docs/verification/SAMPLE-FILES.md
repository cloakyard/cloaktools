# Sample Files verification

Verified 16 November 2026 in **0.5.2 (18)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **161 passing core tests**.

## Scope and UX

Sample Files appears in the optional Developer Tools category and File → Developer Tools. One compact window offers JSON, CSV, Text and Binary. JSON/CSV accept 1–10,000 synthetic records with fixed ID, name, example email, boolean and note fields. Notes cycle through commas, quotes, line breaks and Unicode. Text and zero-filled binary accept exact whole-number sizes from 1 byte through 32 MiB, in Bytes/KiB/MiB units. No real source data is read.

Generate prepares an immutable result in memory and shows its exact byte count. A text preview is limited to 8,192 bytes at a UTF-8 boundary; binary shows the first 64 bytes as hex. Copy Text includes all JSON/CSV/text data and is absent for Binary. Save File reviews the name and destination before publishing the exact prepared bytes. Collisions get numbered filenames. Format/count/size changes remove stale results and save actions; invalid input has inline recovery guidance. Saved output offers Show in Finder and a single Done action. All work stays local with no sample history.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **161 tests passed in 1.214 seconds.** Eight new tests cover deterministic JSON schema/content, CSV quotes/delimiters/multiline fields, exact text/binary sizes through 32 MiB, strict input parsing and overflow, typed-request bounds before allocation, 10,000-record outputs and UTF-8 preview boundaries, exact-byte saving with numbered collisions/unsafe names/staging cleanup, and cancelled generation.
- Native Debug build succeeded. The existing App Intents metadata-skipped notices remain; no new compiler errors or warnings were reported.
- Astro reported zero errors/warnings/hints, built seven routes, and passed local links/assets, canonical metadata, landmarks and pinned Air hashes.

Logs: [core tests](sample-files-core.txt), [native build](sample-files-build.txt), [website](sample-files-site.txt).

## Live native observations

Reviewed the 560 × 570 pt content window in the user's current dark appearance, using the shared Liquid Glass actions and native text preview.

1. Opened Sample Files from Developer Tools. Default JSON offered 10 records and a filename; Generate produced a scrollable preview with **10 records · 1,491 bytes**, Copy Text and Save File.
2. Explicitly saved `Sample data.json` in the temporary verification folder. Success named the saved file and showed Show in Finder/Done. Independent Python JSON parsing verified all 10 records and the embedded line break.
3. Switched to CSV. The prior result and saved status cleared. Generated five records and saved `Sample data.csv` (**354 bytes**). Python's CSV reader verified five records, doubled quote handling, embedded newlines and Unicode notes matching JSON.
4. Switched to Text and saved `Sample file.txt` at 1 KiB. Independent inspection verified **1,024 ASCII bytes**, the repeated line and partial final line.
5. Switched to Binary, chose MiB and generated one unit. The UI displayed the exact **1,048,576-byte** size, a four-line hex preview and Save File without Copy Text. Saved `Sample file.bin`; independent inspection verified its length and that every byte was zero. Numbers use the system locale's grouping.
6. Entered 33 MiB. The old preview/save action disappeared; Generate was disabled with a visible size-limit/unit explanation. Switching back to JSON ignored the irrelevant invalid size. A zero record count disabled Generate with a 1–10,000 recovery message.
7. Closed the sample window, verified the File → Developer Tools → Sample Files menu entry and returned settings to New Files. The final preference JSON matched the snapshot taken immediately before testing. No system defaults or saved workflow libraries changed. Copy Text was not invoked during this feature's UI check.

Synthetic outputs remain in `/tmp/CloakTools-Sample-Files-Verification`. No user source files were used or modified.

Screenshots: [JSON](../../assets/screenshots/sample-files-json-dark.png), [binary](../../assets/screenshots/sample-files-binary-dark.png), [invalid size](../../assets/screenshots/sample-files-error-dark.png).

## Website and remaining checks

Install, Support, Source and Privacy now explain the optional tool, schema, limits and review-before-save flow. Desktop and 320 × 740 previews were inspected; document width matched the 320 px viewport without horizontal overflow. The responsive override was reset, the temporary tab closed and the owned dev server stopped.

Screenshots: [desktop guide](../../assets/screenshots/sample-files-guide-desktop.jpg), [mobile guide](../../assets/screenshots/sample-files-guide-mobile.jpg).

The fixed schema has no custom columns or random seed. Zero-filled binary is for file-size testing, not realistic compression ratios; text may end mid-line. Configuration imports and image/media fixture generation remain future work. Core tests cover maximum sizes and filename collisions; live UI covered the smaller examples above. Native Copy Text beyond the preview limit, exact minimum-size resizing, light appearance, Reduce Transparency/increased contrast and spoken VoiceOver for this window remain broader checks. This is an ad-hoc signed local preview; distribution and notarization are outside this change.
