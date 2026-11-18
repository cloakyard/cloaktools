# CloakTools identity and captures

The icon is an original cobalt tool case containing a beveled silver spanner and fluted amber screwdriver, on an ice-colored ground. A recessed rear tray, raised front rim, darker case return and brushed latch give the silhouette depth. Bold filled shapes and a distinct palette follow Cloakyard's app family without reusing a sibling's pictogram.

## Canonical native source

`icon/CloakTools.icon` is an editable Icon Composer document: eleven full-canvas 1024 × 1024 SVG layers in three independently shaded depth groups, native background fill, material/shadow configuration, and dark fill specializations. Front-to-back, the groups contain the case/rim/latch, the tools and their facets, and the recessed tray. The artwork is not pre-masked or baked into a rounded PNG. Xcode compiles it directly as the `CloakTools` app icon. macOS supplies its mask, material and lighting.

```sh
swift scripts/make-app-icon.swift
node scripts/sync-brand.mjs
```

Run from the repository root. The first command uses Xcode's `ictool` to produce Default, Dark, Clear Light/Dark and Tinted Light/Dark appearance previews, small-size previews and the app's About image set. Native icon compilation does not require manually rerunning the preview generator. The second derives the circular web SVG from every group's paths in back-to-front paint order and copies the native default PNG for web metadata. Site `predev` and `prebuild` run this synchronization automatically. Neither command reads a sibling repository.

- `icon/Previews`: native exports, including 16/32/64/128 pt legibility checks.
- `logo/cloaktools-mark.svg`: derived circular family web mark.
- `screenshots`: actual app and local-browser captures. Older MVP 0 captures remain historical evidence.

The [November 17 icon verification](../docs/air/ICON-2026-11-17.md) records the layered refinement, before/after comparison, appearance exports, native build and website regression coverage.

## Reference study

Read-only references were CloakDrop's teal drop/shield with directional arrow, and CloakRoll's ivory landscape with purple mountains and an apricot sun. Their editable SVG layers, Icon Composer documents, native preview generators, app integration and separate circular website adaptations informed this implementation. CloakRoll's native appearance export pipeline was adapted here. No reference repository was modified.

Apple's [Icon Composer guidance](https://developer.apple.com/icon-composer/) and [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/) informed the native layering and appearance treatment. The web mark is intentionally flatter than the rendered macOS icon, matching the family websites.

## Website captures and social card

`screenshots/new-files-light.png` and `screenshots/new-files-dark.png` show the actual 0.6.0 (26) New Files window, captured on November 17 at 1100 × 850 points (2200 × 1700 pixels). Creation, saved templates, file sets, folder presets and text tools fit in one view. Capture the window with macOS's native window capture, without the pointer, shadow or capture-tool badge; do not add arrows or annotations. Restore the original system appearance afterward. Asset sync copies this pair to `apps/site/public/images/new-files-{light,dark}.png`; the root README uses the same canonical captures. See the [capture verification](../docs/air/NEW-FILES-2026-11-17.md).

The older `roadmap-{light,dark}.png` Conversions captures remain historical evidence for the November 16 native audit. They are no longer website inputs. Other dated screenshots referenced by verification documents also remain intact.

`social/og.png` is a designed Air 1.7.5 card, not an app screenshot. Its configuration is `artwork/social.json`; the full shared template and renderer are in `docs/air`. Build the site, run `node docs/air/render-social.mjs` with the documented browser-authoring dependency, rebuild and run website verification. The initial November 17 card was captured through the host’s approved browser-control tool using that exact template, light appearance, reduced motion, a 2× settled-artwork crop and a 1× 1200 × 630 PNG export. Browser layout evidence accompanies the Air audit.

The sidebar uses 44- and 88-pixel renditions of the 44-point product icon for standard and Retina displays. Regenerate its light and dark artwork from the repository root with `apps/macos/scripts/export-sidebar-icon.sh assets/icon/CloakTools.icon`. The exporter downsamples a 1024-pixel Icon Composer render of each appearance.
