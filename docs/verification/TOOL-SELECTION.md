# First run and optional Developer Tools

Verified 16 November 2026 on macOS 27.2.1 (26B131), Apple silicon, Xcode 27.2 / macOS 27.2 SDK / Swift 6.4.2. Native local preview **0.5.0 (16)**. No public release or site deployment.

## Experience

Fresh installations show a 460 pt welcome sheet with the native app icon, an Included everyday-tools row, an optional Developer Tools switch (Off initially), and one Glass **Start Using CloakTools** action. The choice is saved before dismissal. General → Your tools provides the persistent switch. The welcome sheet does not recur after a completed choice.

Everyday tools remain available in both modes. Everyday New File offers plain text, Markdown and PDF; Copy As offers names, full paths, file URLs and Markdown links. Enabling Developer Tools adds JSON and all 13 programming languages, source-file starting sets, shell arguments and JSON path lists. The optional Developer Tools sidebar category holds Hello World and the language grid, keeping those controls out of New Files.

Known technical custom templates and their saved presets/sets are hidden when the group is Off, but never removed. Classification uses type/extension metadata, not content inspection. Missing references remain visible for repair. Favorites and language choices remain stored. Existing operation drafts retain their captured catalog/settings. Hidden explicit programming requests are rejected with an explanation, without silently choosing another type.

Older preferences migrate with Developer Tools On and the first-run choice complete, preserving the previous catalog. This is a visibility preference, not a security boundary or permission grant. JSON validation and Base64 encoding/decoding remain planned for the optional developer group; no inactive placeholders were added.

## Architecture

`Preferences` adds `developerToolsEnabled` and `hasChosenTools`, distinguishing a missing file from a decoded legacy file. An unavailable Developer Tools category normalizes to General. `ToolAvailability` centralizes categories, template visibility, saved-reference classification and copy formats. The host filters new operation snapshots; stores keep all definitions intact. Preset editors and Copy As retain their opening choices.

Finder's menu is intentionally fixed and compact: Plain Text, Markdown, PDF, Choose File Type or Template, and clipboard creation. The catalog handoff reads host preferences at invocation. This avoids sandbox-breaking preference reads, a settings cache, new entitlements or a Finder restart requirement. Existing Finder monitoring/signing boundaries are unchanged.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **134 core tests passed** in 1.104 seconds: previous 128 plus six policy/migration tests. Coverage includes missing-file defaults, persisted completion, legacy choice/favorite preservation, everyday versus full catalogs, immutable snapshots, disabling/re-enabling without resetting language choices, hidden-category recovery, metadata classification and non-destructive saved workflow visibility. [Core log](tool-selection-core.txt).
- Final native Debug arm64 build: **BUILD SUCCEEDED**, bundle **0.5.0 / 16**, no Swift warnings. Expected unused AppIntents metadata warnings remain. [Build summary](tool-selection-build.txt).
- Website: **7 routes**, zero errors/warnings/hints. Local links/assets, canonical metadata, landmarks and pinned Air hashes pass. [Site log](tool-selection-site.txt).

## Actual native checks

1. Quit the previous app, backed up its original preferences, and temporarily removed only that preferences file to exercise a real fresh launch. Other saved libraries were left intact.
2. Welcome appeared with Developer Tools Off. Started in everyday mode; the sidebar omitted Developer Tools. New Files showed plain text, Markdown and PDF without the language grid or Hello World switch. The creation picker contained those three types plus the existing synthetic Markdown template, with no JSON/source types.
3. Copy As for a synthetic note showed exactly four everyday formats, excluding shell arguments and JSON. Cancelled without copying or creating output.
4. General's switch immediately added the Developer Tools sidebar category. Its grid exposed all 13 languages. In the temporary test preferences, enabled Hello World and disabled Rust, then turned Developer Tools Off and quit.
5. Relaunch retained everyday mode and did not repeat welcome. Turning Developer Tools On restored Hello World On and Rust Off. The enabled creation picker showed all 17 built-ins, including C, C++, Rust and JSON, plus the saved template.
6. Live layout review moved the welcome switch to the card's trailing edge and shortened a long helper line in Developer Tools. Rebuilt and visually checked the corrected layout. The everyday file-set UI also omits a redundant single-choice starting menu, and regular after-creation guidance avoids source-code wording.
7. Repeated a fresh launch on the corrected build. The optional switch remained Off initially; enabled it and pressed Return. The sheet dismissed and the developer category appeared. The prominent action uses the native Glass style; no system setting or account prompt was involved.
8. Restored the original preferences byte-for-byte. Relaunch showed the original Open With selection, no welcome, and the developer category via legacy migration. Original preferences SHA-256: `aa7dd4d0fde1ce465a1825b1e19eeb82023410899256e5dd9a52b53103ed95a3`.
9. In actual Finder, opened a temporary window at the existing scoped workspace and inspected the selected-folder context menu. It showed the three everyday types and Choose File Type or Template. Invoking the latter opened the host creator at the selected folder with its saved favorite and full developer catalog. Cancelled without output; closed only the temporary Finder window. The registered extension was 0.5.0 and no Finder restart was needed.
10. Relaunched the final build normally. Original preferences still match, and observed web/email defaults remain Google Chrome and Mail. No test recipes, templates or workflows were added; synthetic verification preference copies remain under `/tmp/CloakTools-Tool-Selection-Verification`.

Screenshots: [welcome](../../assets/screenshots/tools-welcome-light.png), [everyday New Files](../../assets/screenshots/tools-everyday-files-light.png), [Developer Tools](../../assets/screenshots/tools-developer-light.png).

## Website checks

Updated Home, Install, Support, Source and Privacy to explain optional developer choices and preserved saved data. Home now uses the actual everyday New Files screenshot, explicitly labeled light appearance, in place of the old language-settings screenshot. The family Air shell, logo and unique finite animation remain unchanged.

Home was inspected at 1728 px and checked for overflow at 320 px. Install and Support were visually inspected at 320 px. All checked pages had `scrollWidth === innerWidth`. The new guide index links updated the fragment and focused the correct headings. [Product screenshot](../../assets/screenshots/tools-site-product.jpg), [mobile first-run guide](../../assets/screenshots/tools-site-guide-mobile.jpg).

Reset the temporary viewport, closed the preview tab and stopped the owned local server. Nothing was published.

## Limits

- Live checks cover both onboarding choices, restart, mode changes, retained language choices, both creation catalogs, everyday Copy As and actual Finder handoff. Technical saved-workflow filtering, missing-reference behavior and normalization are automated core coverage, rather than modifications to the user's libraries.
- Spoken VoiceOver, dark appearance for the new welcome, all accessibility appearance settings, minimum-size/long-localization stress and save-failure injection remain release checks. The new views use existing native semantic controls and shared accessibility-aware Glass fallbacks.
- The toggle is not an execution or access restriction. Already-open operations continue with their captured choices. Developer ID signing/notarization, installer lifecycle, configurable Finder scopes and verified Edge/profile routing remain separate release gates.
