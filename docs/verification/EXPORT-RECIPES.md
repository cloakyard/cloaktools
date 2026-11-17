# Reusable export recipes

Verified 16 November 2026 on macOS 27.2.1 (26B131), Apple silicon, Xcode 27.2 / macOS 27.2 SDK / Swift 6.4.2. Native local preview **0.4.2 (15)**. Development evidence; no public release or site deployment.

## Working path and design

**Save Recipe…** in Convert Image, Make It Fit and Export Media opens a 440 pt native sheet. The name and settings summary sit in a readable card; a concise explanation states that saving creates no output and changes no conversion defaults. Glass Cancel/Save actions remain separate from the operation's export controls. Reused recipes offer Save Changes or an explicit Save as a new recipe choice.

**Conversions → Export recipes → Use…** and **File → Recreate Export** ask for a fresh source with a Review Source action. The existing operation then shows its recipe origin and captured settings. Image conversion requires Convert; fitting requires a fresh Preview Fit followed by Save Copy; media requires Export Copy. Playback does not begin automatically.

Recipe rows have tool icons, titles, output summaries, Use and labeled actions menus. Unsupported media keeps the requested preset visible as unavailable, gives an actionable explanation and disables Export Copy. Selecting an available preset clears that warning without changing the saved recipe. Destination, feedback and Glass actions stay outside the scrolling controls.

## Storage and boundaries

Recipes contain a UUID, title and typed image, fit or media output settings. No source/destination path, output filename, content or history is retained. Names accept 1–80 characters without controls or surrounding whitespace. Up to 32 unique recipes fit in a version-1 JSON archive bounded to 256 KiB. Invalid, malformed, oversized or unsupported archives fail without replacement. Fit byte limits must be representable in whole decimal KB.

Updates reload and compare the original recipe, so an older operation cannot silently replace a changed or removed definition. A separate copy receives a new UUID. Open operations retain their snapshots. Removal affects only the definition. App edits serialize on the main actor; simultaneous external/process writers are not protected by a cross-process transaction lock.

Existing image/media input limits, fit calculations and safe publication remain authoritative. Recipes do not auto-run, watch folders, process batches, store export history or include PDF recipes. Reusing settings does not promise identical output bytes or a successful fit for different source content.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **128 core tests passed** in 1.157 seconds: the previous 120 plus eight recipe tests. These cover every stored setting, independent snapshots, invalid titles and limits, whole-KB validation, duplicate IDs, library/version/size bounds, preserved bytes after rejection, stale edits/removal, explicit copies, saved image/fit recipes with real output, incompatible media and an audio recipe reused against distinct sources. [Core log](export-recipes-core.txt).
- Native Debug arm64 build: **BUILD SUCCEEDED**, bundle **0.4.2 / 15**, no Swift warnings. Expected unused AppIntents metadata warnings remain. [Build summary](export-recipes-build.txt).
- Website: **7 routes**, zero errors/warnings/hints. Local links/assets, canonical metadata, landmarks and pinned Air hashes pass. [Site log](export-recipes-site.txt).

## Actual native interaction

1. Converted the synthetic image draft to JPEG, 65% quality and black background, then saved **JPEG proof**. Cancelled the operation. The recipe was the only new persisted item: no export existed and the preferences file was unchanged.
2. Relaunched and used File → Recreate Export. The fresh-source picker explained its effect and required Review Source. A separate source URL opened with JPEG / 65% / black, without automatic conversion. Convert produced a valid 1920 × 1280 JPEG of 788,538 bytes.
3. Saved **Fit proof** with JPEG, 250 KB, a 640 × 480 bounding box, 45% quality floor, black background and further reduction enabled. Cancelled, then reused it from Conversions. All choices returned, including the advanced summary, with no precomputed fit. Preview measured 640 × 426 and 95,488 bytes. Save Copy wrote exactly that byte count.
4. Saved **Video proof** as MP4 up to 720p, cancelled, then reused it on audio-only WAV. The requested video preset remained visible as unavailable and Export Copy was disabled. Live review found a directional wording error; the final build names the Export as control instead. The warning and actions remain visible in the compact audio layout.
5. Explicitly selected M4A, clearing the warning. Save as a new recipe created **Audio proof** with a different UUID while keeping Video proof. Export Copy produced a valid AAC/M4A file of 302,466 bytes. No playback began automatically.
6. Reused Video proof with the synthetic movie. The review retained 720p, then explicit Export Copy produced a 1280 × 720 H.264/AAC MP4, 12 seconds and 1,263,375 bytes. Native progress appeared while exporting.
7. Relaunched the final build after the UX fixes. All four recipes persisted. The actions menus retained recipe-specific accessibility labels after returning from sheets. Changing a rename draft and pressing Escape left JPEG proof unchanged. The revised compatibility message was visually checked again.
8. Independently decoded both JPEGs and both media files with installed FFmpeg tools. The fitted JPEG matched its measured byte count, and all source hashes matched before/after. No output staging remained. [Output evidence](export-recipes-output.txt).
9. Removed only the synthetic recipe library (it was absent before testing), retained its test copy under the synthetic fixture directory, and relaunched normally. Preferences match their original values. The settings category is restored to Open With; web/email defaults remain Google Chrome and Mail. No OS settings were changed.

Screenshots: [save sheet](../../assets/screenshots/export-recipe-save-light.png), [recipe library](../../assets/screenshots/export-recipes-library-light.png), [fit review](../../assets/screenshots/export-recipe-fit-light.png), [final incompatible-media feedback](../../assets/screenshots/export-recipe-incompatible-light.png).

## Website verification

Home, Install, Support, Source and shared Privacy content now describe recipes. The Privacy index includes Export recipes and its date is 16 November 2026. The pinned family Air shell, existing icon and finite app animation remain unchanged.

The Install guide was visually reviewed at 1728 px and 320 px; Support and Privacy at 320 px. Each checked viewport had `scrollWidth === innerWidth`. The new Install, Support and Privacy index links set the correct fragment and focused the corresponding heading. Text and the long local storage path wrap within the narrow reading column. [Desktop guide](../../assets/screenshots/export-recipes-guide.jpg), [mobile support](../../assets/screenshots/export-recipes-support-mobile.jpg).

The temporary viewport override was reset, preview tab closed and owned local server stopped. Nothing was published.

## Remaining verification

- Live UI exercised image/fit/media saving and reuse, persistence, fresh reviews, incompatible-preset recovery, Save as new and cancelled rename. Stale-edit rejection, successful updates, removal semantics and malformed/versioned libraries were covered in core tests rather than manually injecting invalid user data.
- Light appearance was inspected. Dark appearance, spoken VoiceOver, the full Reduce Transparency/increased-contrast matrix, long localized titles, minimum-size interaction and all 32-row combinations remain broader release checks.
- Existing filesystem, codec, memory/performance, abrupt termination/recovery and cancellation limitations remain as documented for the underlying operations. Recipe persistence does not add a cross-process locking guarantee.
- Developer ID signing/notarization, installer/update lifecycle, supported App Group Finder scopes and verified Edge/profile routing remain open. The next Milestone 4 feature is reviewed synthetic test files and fixtures.
