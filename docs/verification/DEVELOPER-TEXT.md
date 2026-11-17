# Developer text utilities verification

Initial JSON/text checks verified 16 November 2026 against local preview **0.5.1 (17)** on Apple silicon, macOS 27.2.1, Xcode 27.2 / SDK 27.2. The subsequent [image Base64 extension](BASE64-IMAGES.md) brings the combined suite to 153 passing tests. This is a local development build, not a published release.

## Implemented scope

- Optional Developer Tools includes JSON Format, Minify and Validate, and Base64 UTF-8 text Encode/Decode with Standard and URL-safe alphabets.
- The sidebar exposes two compact tool rows; File → Developer Tools exposes the same actions. Both entry points disappear when the group is Off. A fresh persisted preference also guards tool creation.
- Native 600 × 600 pt windows use plain monospaced input, a read-only result, byte counts, explicit processing/copying, inline errors and shared Glass actions. Validation removes the result pane and Copy Result. Command-Return runs; Return edits text.
- JSON output preserves number spelling/precision, keys/order/duplicates and string escapes. Strict grammar and Unicode escape checks report one-based line/scalar-column locations. Input is capped at 1 MiB, nesting at 128 containers and formatted output at 8 MiB.
- Base64 accepts ASCII whitespace and omitted padding, checks alphabet/padding/canonical pad bits, and rejects non-UTF-8 decoded data. URL-safe output omits padding. Input is capped at 1 MiB.
- Processing runs away from the main actor. Edits, option changes and close cancel pending work and invalidate its revision. Results are previewed up to 65,536 characters; explicit copying uses all output. Text is not saved, logged or sent over the network.

## Automated evidence

Commands completed successfully:

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

**146 core tests passed** in the final run (1.161 seconds). The 12 new tests cover exact JSON tokens/large numbers, top-level values/containers, malformed grammar/escapes/surrogates, Unicode/CRLF error positions, depth and expansion limits, RFC Base64 vectors, Unicode/NUL round trips, alphabets, padding/pad bits, binary rejection, UTF-8 byte limits and agreement with Foundation on generated ordinary JSON.

The native Debug build succeeded. Xcode emits its existing App Intents metadata-skipped notice because no AppIntents dependency is linked. The site reports zero Astro errors/warnings/hints, builds seven routes and passes local asset/link, canonical metadata, landmark and pinned Air checks.

Logs: [core](developer-text-core.txt), [native build](developer-text-build.txt), [site](developer-text-site.txt).

## Observed native behavior

- Both tool rows opened native windows. File → Developer Tools → Base64 opened a fresh empty session.
- JSON Format preserved the exact large integer `9007199254740993123456789`. Minify returned compact output. Validate showed success without a result pane.
- Invalid JSON with a trailing comma reported **Line 3, column 20: Remove the trailing comma.** Input stayed intact and Copy Result was unavailable.
- Changing actions cleared output. Return inserted one newline, invalidated output and disabled Copy Result; native Undo restored the original input. Command-Return processed the current text.
- Standard Base64 encoded `CloakTools · नमस्ते 🚀`. Copy Result, native paste into Decode, and explicit Decode returned exactly that text. URL-safe encoding produced `-` instead of `+` and omitted padding; URL-safe decoding returned the same Unicode text.
- Decoding `/w==` explained that the result was not UTF-8 text. Pasting 1,048,577 ASCII bytes was rejected with an inline size error while the previous four-byte input stayed intact.
- Disabling Developer Tools removed the sidebar category and File submenu immediately. The existing Base64 window retained its input/options/result and still decoded successfully, matching the open-operation policy.
- Closing and reopening tools started empty sessions. Test windows were closed and the original preference file was restored byte-for-byte (SHA-256 `aa7dd4d0fde1ce465a1825b1e19eeb82023410899256e5dd9a52b53103ed95a3`). The app was reopened to Open With; Chrome and Mail remained its observed system defaults. No template libraries or output files were changed.
- Copy testing used synthetic text on the system clipboard. A browser-session clipboard snapshot was restored, but that API did not reflect native clipboard writes; native clipboard restoration is not claimed.

The visual audit found crowded multiline JSON rendering with the default native text layout. Explicit TextKit 1 backing fixed the displayed line breaks and indentation; the final screenshot shows separate array entries. Automatic text substitutions/completion, spelling, link/data detection and rich text are disabled for these editors.

Screenshots: [JSON](../../assets/screenshots/developer-json-light.png), [validation error](../../assets/screenshots/developer-json-error-light.png), [Base64](../../assets/screenshots/developer-base64-light.png).

## Observed website behavior

Install, Support, Source and Privacy content now describes implemented tools, optional visibility, shortcuts, limits and local processing. The existing Cloakyard/Air styling is retained. The Install section was visually reviewed on desktop and at 320 × 740; measured content width equals the 320 px viewport, with wrapping and no horizontal overflow. The responsive override was reset, the temporary tab closed and the owned Astro server stopped.

Screenshots: [desktop guide](../../assets/screenshots/developer-text-guide-desktop.jpg), [mobile guide](../../assets/screenshots/developer-text-guide-mobile.jpg).

## Remaining coverage

The native light appearance was reviewed. The exact minimum window size was not established through the live resize control; minimum-size/localization, spoken VoiceOver, increased contrast, Reduce Transparency and the broader appearance/runtime matrix remain release checks. Size/expansion boundaries were tested in core; sustained large-editor performance and full-result clipboard copying beyond the preview limit were not independently measured. Developer ID signing, notarization and public distribution remain separate release gates.
