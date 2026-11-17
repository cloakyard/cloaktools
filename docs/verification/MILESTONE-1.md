# Identity, website and first Milestone 1 slice

Verified 15 November 2026 on Apple silicon, macOS 27.2.1 (26B131), Xcode 27.2 (27B52), SDK 27.2, Swift 6.4.2. App version **0.1.0 (2)**, local ad-hoc Debug build. The [MVP 0 record](MVP-0.md) remains the evidence for the original Finder creation, image conversion and actual HTTP/HTTPS/mailto event paths. This update completes a defined Milestone 1 file slice, not all of Milestone 1 or a public beta.

## Implemented scope

- 17 built-in types: 13 programming languages, text, Markdown, JSON and PDF. JSON contains a valid empty object; PDF contains one real blank A4 page.
- Imported single-file UTF-8 templates, copied bytes, editable titles and default filenames, favorites, removal and a Finder “Choose a Saved Template…” entry. Import limits: 1 MiB each, 64 entries / 16 MiB content per library. Original sources remain untouched.
- Immutable operation content/settings snapshots. Imported content remains explicit even when Hello World is Off. Existing preferences migrate without losing retained language choices.
- Open After Creation, Off by default, using explicit TextEdit for text/source/imports and Preview for built-in PDF. Code is never executed.
- Original layered native icon, native appearance exports, matching web mark and updated About screen.
- Family website redesign with a distinct finite file animation and current native screenshots.

## Native runtime evidence

The native import panel selected the synthetic `scripts/fixtures/Project Note.md` fixture (63 bytes, CRLF). The saved template was starred, its default filename changed to **Project Plan**, and its content preview inspected in the compact details sheet.

An actual blank-space Finder context menu in `~/CloakTools Files` exposed the expanded catalog and **Choose a Saved Template…**. Selecting it opened the compact creator with **Project Plan.md**, the favorite indicator and “Saved content · 63 bytes”, while the Hello World master was Off. Return created the file. With Open After Creation enabled, TextEdit opened that document; the visible text matched the fixture, and a byte-for-byte comparison against the original fixture passed, preserving CRLF. No code was run.

A real `cloaktools-action` creation event for PDF produced **Blank page proof.pdf** in the same folder. Preview opened it and displayed one blank page. Core tests independently decoded its format and page dimensions using Core Graphics.

After a clean build/relaunch, the saved template, favorite state and **Project Plan** default name persisted. The updated sheet exposes separate accessibility labels for title/default filename; the favorite exposes its state. About showed the new native icon and **0.1.0**. Light/dark settings and compact template details were inspected. The template menu was tightened to an icon-only ellipsis after visual review.

The final app was relaunched following system appearance, with Hello World **Off**, all 13 language choices retained, and Open After Creation **Off**. The synthetic saved template remains available for trying the feature. Debug-only `--appearance=light` / `--appearance=dark` flags were used for captures; global macOS appearance settings were not changed.

Actual captures:

- [Light settings](../../assets/screenshots/settings-m1-light.png) · [Dark settings](../../assets/screenshots/settings-m1-dark.png)
- [About and native icon](../../assets/screenshots/about-m1-light.png)
- [Saved-template creator](../../assets/screenshots/saved-template.png)
- [Compact details sheet](../../assets/screenshots/template-details-dark.png)
- [Blank PDF in Preview](../../assets/screenshots/blank-pdf-proof.png)

Some operation captures contain macOS's screen-sharing badge/cursor highlight; those are capture UI, not app controls. Settings captures show Hello World enabled for legibility; the final preference was restored Off.

## Brand and website evidence

Read-only study included both siblings' actual editable SVG layers, Icon Composer JSON, native export scripts, website marks, header/footer/layout/navigation/CSS and artwork lifecycle. Their repositories remained clean after this work.

The six-layer `assets/icon/CloakTools.icon` compiles directly through Xcode. Clean-build bundle metadata names **CloakTools**, with `CloakTools.icns` and `Assets.car`; the old bitmap `AppIcon.icns` is absent. Native exports cover Default, Dark, Clear Light/Dark and Tinted Light/Dark; each was visually inspected along with small-size output. `scripts/sync-brand.mjs` derives the circular website mark from the same foreground layers. See [asset sources](../../assets/README.md).

The website uses the same shared header/navigation, footer, typography, spacing, hero/section structure, policy and 404 conventions as CloakDrop and CloakRoll. Content follows their rhythm while describing CloakTools' actual features. Source/License stay honest local routes until publication. The pinned Air stylesheet and shared artwork helper retain their recorded hashes.

The unique three-document animation runs for **2.46 seconds** (2200 ms plus 0/130/260 ms delays), once, with deliberate replay. Browser inspection observed all three animations running after Replay, then all three paused with `data-art-state="offscreen"` after navigating to Download; keyboard focus moved to that section. The finished state was `complete`. Reduce Motion changed state to `reduced`, hid Replay and left zero active animations. With JavaScript disabled, all three documents remained visible at opacity 1 in their completed arrangement. No indefinite loop or layout animation is used.

Responsive browser checks had no horizontal overflow at 320×740, 390×844, 768×900, 1024×900, 1440×1000, 1920×1080 and 844×390. All six supporting routes were also checked at 390 px: expected headings/main landmarks, no overflow and no missing decoded images. Mobile Menu opens; Escape closes it and returns focus to the summary. Light/dark rendering, the policy layout, complete desktop page and 200% root text sizing at 390 px were inspected. Text scaling is not a claim of browser zoom or full assistive-technology testing. Browser console had no warning/error entries in the captured final session.

- [Desktop preview](../../assets/screenshots/website-m1-preview.png)
- [Full desktop page](../../assets/screenshots/website-m1-desktop.png)
- [Phone, dark](../../assets/screenshots/website-m1-phone-dark.png)
- [Measured layout/route results](m1-browser-layouts.json)

Browser emulation and viewport overrides were reset after QA. No deployment, DNS change, public repository creation or release upload was performed. The owned local QA server is stopped at handoff.

## Commands and results

```sh
# Native previews, including all six system appearances
swift scripts/make-app-icon.swift
node scripts/sync-brand.mjs

# Native app and embedded Finder extension
./scripts/build-native.sh

# Dependency-free core
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore

# Independent website
(cd apps/site && npm run verify)
```

Results: native build **succeeded** after a clean build and final UI refinement. Core **18 tests passed**, including a parameterized 13-language test. Website: **0 errors, 0 warnings, 0 hints**, seven static pages built; local assets/links, metadata, landmarks and pinned Air hashes passed. [Core output](m1-core-tests.txt) · [Website output](m1-site-verification.txt).

New meaningful tests cover old-preference migration, valid JSON/PDF under either master state, exact UTF-8/CRLF saved bytes and immutable snapshots after source edits/library removal, rejection of malformed/binary/oversized/unsafe templates, and strict saved-template intent decoding. The existing publication, collision/concurrency, image, cancellation and routing tests continue to pass.

Measured Debug app including its extension: **5532 KiB allocated on disk** (`du -sk`), approximately 5.40 MiB. A post-launch idle `ps` sample reported **0.0% CPU**, **119712 KiB RSS** and **0.53 seconds cumulative CPU**. These are single-machine snapshots, not sustained energy or Release benchmarks.

## Remaining acceptance and next work

The local MVP 0 functional paths remain verified, and this Milestone 1 slice works end to end. Full spoken VoiceOver, real system Reduce Transparency/Increase Contrast settings, macOS 27.0 runtime, localization/extreme resizing, broader cloud/virtual/protected-folder contexts, and signed installer/extension lifecycle remain release acceptance work. The historical Mail compose/account outcome remains unconfirmed; exact mailto dispatch was verified with the separate native receiver. No mail was sent.

Next: user-selected Finder scopes and persistent folder access, clipboard text/image creation, more native image output directions, images-to-PDF/PDF merging and Copy As. Milestone 2 then adds explicit default-handler setup/restoration, destination management and ordered routing rules. The host remains intentionally unsandboxed for the local preview; broader Finder access requires the documented permission strategy review. Developer ID signing/notarization and public distribution are still outstanding. No external dependency blocks the completed local slice.
