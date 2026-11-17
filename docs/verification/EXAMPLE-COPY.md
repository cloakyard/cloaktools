# Example Copy verification

Verified 16 November 2026 in **0.5.3 (19)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The combined implementation has **170 passing core tests**.

## Scope and design

Example Copy is available in optional Developer Tools and its File submenu. Choose a UTF-8 JSON or environment file up to 1 MiB. The tool captures and prepares an example in memory; a compact Example/Source switch compares read-only previews. Save Example and Copy Example always target the prepared example and return the visible preview to Example on success. The original is never overwritten.

JSON keys, order, duplicate keys and object/array structure remain. Strings become `"REPLACE_ME"`, numbers `0`, booleans `false`, and null stays null. Environment variable names, order, duplicates and optional export remain; all values become `REPLACE_ME`, with comments/blank lines removed and LF output. Only single-line assignments are supported. The tool does not evaluate expressions or run code.

Retained keys, names and structure can contain private information; the interface explicitly asks users to review them before sharing. This is a placeholder generator, not a secret detector or anonymization guarantee. Environment output defaults to a visible `Environment example.env`, consistent with the shared writer's existing filename restrictions.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **170 tests passed in 1.099 seconds.** Nine new tests cover every JSON scalar type, key order/duplicates/escaping, top-level values and UTF-8 BOMs, malformed grammar/depth/output expansion, environment quoting/comments/export/duplicates, unsupported syntax without echoed values, unsupported/binary/oversized input, Unicode-safe bounded previews, immutable capture and exact saving with source/filename collisions, plus cancelled preparation/capture/publication. The existing formatter/minifier/validator tests remain green.
- The final native Debug build succeeded. Only the existing App Intents metadata-skipped notice was reported.
- Astro reported zero errors/warnings/hints, built seven routes and passed local links/assets, canonical metadata, landmarks and pinned Air hashes.

Logs: [core tests](example-copy-core.txt), [native build](example-copy-build.txt), [website](example-copy-site.txt).

## Live native verification

Reviewed the 600 × 600 pt content window in the user's current dark appearance with shared Liquid Glass actions.

1. Opened Example Copy from Developer Tools and selected the synthetic `Configuration.json`. The source card showed JSON and six scalar values. Its 164-byte example kept the nested object/array structure and replaced the name, token, number, boolean and URL values; null remained null.
2. Switched to Source, showing the captured 189-byte input. Saved while Source was selected. Independent Python parsing verified that the output contained the expected placeholders, not source values, and the original JSON retained its content.
3. Found and fixed a stale accessibility label on the shared native text view: `updateNSView` now refreshes the label when the preview mode changes. The final build's Source view reported **Original source preview**, and Example reported **Example copy preview**.
4. Improved completion to return the visible preview to Example after a successful copy/save, so it matches the bytes produced. This was observed in the final environment save flow.
5. Chose the hidden `.env.demo`. Four assignments became an 84-byte example, retaining `export PORT` and the other variable names while removing the comment and values. Compared Source, then saved `Environment example.env`. Completion switched to Example, named the saved file, and offered Show in Finder/Done. Independent byte comparison verified all four placeholder assignments and the unchanged 112-byte source.
6. Replaced the source with `Invalid.env`, containing an unsupported multiline value. The previous preview, saved status and Save action cleared. The error identified line 2 without echoing the value and offered another file selection. No example file was published.
7. Verified the File → Developer Tools → Example Copy entry, closed the test window and returned to New Files. Preferences matched the snapshot from immediately before testing. System defaults and workflow libraries were not changed. Copy Example was not invoked during this feature's UI check.

All fixtures and outputs are synthetic and contained in `/tmp/CloakTools-Example-Copy-Verification`. No real configuration or credential files were read.

Screenshots: [JSON example](../../assets/screenshots/example-copy-json-dark.png), [saved environment example](../../assets/screenshots/example-copy-env-saved-dark.png), [unsupported multiline input](../../assets/screenshots/example-copy-error-dark.png).

## Website verification

Install, Support, Source and Privacy describe placeholder rules, retained names/structure, comparison and explicit saving. Desktop and 320 × 740 browser previews were inspected. At mobile width, the document and viewport both measured 320 px without horizontal overflow. The temporary viewport override was reset, the test tab closed and the owned dev server stopped.

Screenshots: [desktop guide](../../assets/screenshots/example-copy-guide-desktop.jpg), [mobile guide](../../assets/screenshots/example-copy-guide-mobile.jpg).

## Boundaries and remaining checks

JSON limits are 128 nesting levels and 8 MiB of output. Both preview panes show at most 65,536 characters; save/copy includes the complete example. Source and result stay in memory until the window closes. Unsupported inputs include YAML/TOML/INI/CSV, binary files, multiline environment values, continuations, mixed quoted/unquoted values and shell scripts. Placeholders may not satisfy the original configuration's schema or run-time requirements.

Core tests cover size/depth boundaries, cancellation and numbered collisions. Live UI covered the smaller fixtures above. Full-size clipboard performance, source replacement during slow reads, exact minimum-size resizing, light/contrast/Reduce Transparency coverage and spoken VoiceOver remain broader checks. This is an ad-hoc signed local preview; signing, notarization and distribution remain release work.
