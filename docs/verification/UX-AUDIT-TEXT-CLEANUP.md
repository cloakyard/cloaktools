# UX/UI audit and follow-through

Audited 16 November 2026, concluding in **0.5.5 (21)**. The audit fixes were implemented and built before beginning the next feature, everyday Text Cleanup. Later live cleanup testing exposed a shared completion-focus problem; that correction was applied across the affected tools before finishing.

## Scope and evidence

This is an implementation and focused live UX review, not a claim that every historical workflow was rerun with every accessibility setting.

| Area | Review in this pass | Outcome |
| --- | --- | --- |
| Shared native design | Source review of headings, semantic cards, Glass/solid fallback, status, destination rows, operation sizing and action shortcuts | Retained the existing native design system; unified compact launcher rows and newer-tool completion |
| New Files and developer tools | Live settings navigation, new digest empty state, source review of tool availability and action states | Combined everyday launchers; reduced repeated prose; named Open actions retain accessibility labels |
| Images, PDF and media | Live Conversions layout; source review and existing regression suite for operation behavior | All five launch actions now visible at default size; recipes/defaults and detailed limits follow |
| Routing/defaults | Live Open With overview and actual Google Chrome/Mail status; source/previous verification review | Existing explicit setup/restore/rule structure retained; no defaults changed |
| JSON/Base64 and generated text tools | Source review of invalidation/save/copy states, live Base64 image entry/decode/name error and Escape | Fixed primary-action hierarchy, inline filename validation, contradictory status and same-value binding invalidation |
| Save completion | Live Text Cleanup save while viewing Input, repeated saves and keyboard completion | Fixed embedded AppKit editor consuming the first Return; final build finishes with one Return |
| Website | Desktop home/product/guide and 320 × 740 mobile home/menu/guide, current screenshot, metadata and seven-route verification | Updated stale product imagery, shortened dense Craft copy, verified no horizontal overflow, Escape recovery and finite animation completion |

Prior feature-specific records remain the evidence for first-run migration, clipboard capture, conversion matrices, routing setup/restoration and the other historical integration paths. Their existing core tests remain green.

## Fixed deviations

1. **Launch actions were buried.** Conversions opened with recipe guidance and defaults, pushing PDF/media actions below the first screen. It now begins with Images and PDFs & media groups. All five tools are visible at the default 900 × 650 settings size. Detailed format constraints remain available in a disclosure and individual reviews.
2. **New Files repeated large descriptions.** Clipboard and digest launchers now share compact rows under Text & clipboard. Text Cleanup follows the same pattern. Developer tool rows use the same shared component and named accessibility actions.
3. **Base64 Image showed a disabled primary action before selection.** Choose Image is now the prominent first step, then Encode. The redundant secondary picker is replaced by Change only after capture.
4. **Invalid image names failed late.** Decoded image filenames validate inline and disable Save before the folder chooser. A synthetic 1 × 1 PNG decoded successfully; `../invalid` showed a clear error and disabled Save. The final status says Image decoded, avoiding the former contradictory Ready to save wording.
5. **Same-value field commits could clear state.** JSON/Base64 options/input and newer filename observers compare old/new values before invalidating. Digest selection also avoids switching views when unchanged. Existing results and save feedback survive unchanged focus commits. Text comparisons use exact UTF-8 bytes so canonically equivalent Unicode with different byte representations still invalidates old results. The shared editor uses the same comparison when refreshing its text. Live final-build verification encoded precomposed é as `w6k=`, replaced it with decomposed e + combining acute, observed the byte count change from two to three and Copy become disabled, then encoded the new input as `ZcyB`.
6. **Completion shortcuts differed and the editor swallowed Return.** Base64 Image, Sample Files, Example Copy, Markdown Digest and Text Cleanup now use Return for Done and Escape for closing outside publication. A window-specific weak callback releases the embedded native editor after saving. The final Text Cleanup save showed the window as first responder and one Return closed it. This does not move focus in unrelated windows.
7. **The digest empty preview gave no guidance.** It now explains that selecting files enables content inspection.
8. **Website imagery/copy lagged the app.** The product and social-preview image now show current New Files. Its caption explicitly identifies optional Developer Tools and dark appearance. The long Craft roadmap paragraph is shorter; detail remains in Source. The pinned Air assets, family layout and finite artwork remain unchanged.

## Evidence

Native: [Conversions](../../assets/screenshots/ux-audit-conversions-dark.png), [New Files](../../assets/screenshots/ux-audit-new-files-dark.png), [Base64 entry](../../assets/screenshots/ux-audit-base64-entry-dark.png), [final filename error](../../assets/screenshots/ux-audit-base64-validation-dark.png).

Website: [updated product](../../assets/screenshots/ux-audit-site-product-desktop.jpg), [mobile home](../../assets/screenshots/ux-audit-site-mobile.jpg), [desktop guide](../../assets/screenshots/text-cleanup-guide-desktop.jpg), [mobile guide](../../assets/screenshots/text-cleanup-guide-mobile.jpg).

The initial [audit-only native build](ux-audit-build.txt) passed. Final feature validation passed **189 core tests**, the native build and seven website routes. See [Text Cleanup verification](TEXT-CLEANUP.md) for final logs and functional observations.

## Remaining review boundaries

Live native checks used the current dark appearance. A narrower cleanup window remained readable, but exact minimum dimensions for every dialog were not verified. Light appearance, full keyboard traversal, VoiceOver speech, increased contrast, Reduce Transparency, localization and the entire OS/runtime matrix still need dedicated release testing. The shared Glass fallback is source-reviewed; it was not exercised by changing the user's system appearance/accessibility preferences.

No clipboard copy action or default-handler setup was invoked in this pass. Google Chrome and Mail remained defaults. Navigation returned to New Files and saved preferences matched the pre-test snapshot. Test windows/tabs and the temporary site server were closed. No public release or deployment was performed.
