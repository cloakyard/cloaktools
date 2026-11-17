# CloakTools identity and captures

The icon is an original tool tray containing a silver spanner and amber screwdriver, on an ice-colored ground with a cobalt tray. Bold filled shapes and a distinct palette follow Cloakyard's app family without reusing a sibling's pictogram.

## Canonical native source

`icon/CloakTools.icon` is an editable Icon Composer document: six full-canvas 1024 × 1024 SVG foreground layers, native background fill, material/shadow configuration, and dark fill specializations. The artwork is not pre-masked or baked into a rounded PNG. Xcode compiles it directly as the `CloakTools` app icon. macOS supplies its mask, material and lighting.

```sh
swift scripts/make-app-icon.swift
node scripts/sync-brand.mjs
```

Run from the repository root. The first command uses Xcode's `ictool` to produce Default, Dark, Clear Light/Dark and Tinted Light/Dark appearance previews, small-size previews and the app's About image set. Native icon compilation does not require manually rerunning the preview generator. The second derives the circular web SVG from those same foreground paths and copies the native default PNG for web metadata. Site `predev` and `prebuild` run this synchronization automatically. Neither command reads a sibling repository.

- `icon/Previews`: native exports, including 16/32/64/128 pt legibility checks.
- `logo/cloaktools-mark.svg`: derived circular family web mark.
- `screenshots`: actual app and local-browser captures. Older MVP 0 captures remain historical evidence.

## Reference study

Read-only references were CloakDrop's teal drop/shield with directional arrow, and CloakRoll's ivory landscape with purple mountains and an apricot sun. Their editable SVG layers, Icon Composer documents, native preview generators, app integration and separate circular website adaptations informed this implementation. CloakRoll's native appearance export pipeline was adapted here. No reference repository was modified.

Apple's [Icon Composer guidance](https://developer.apple.com/icon-composer/) and [app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/) informed the native layering and appearance treatment. The web mark is intentionally flatter than the rendered macOS icon, matching the family websites.

## Website captures and social card

`roadmap-light.png` and `roadmap-dark.png` are actual 0.6.0 Conversions windows, captured with synthetic/empty state during the November 16 native audit. Reproduce with the local preview open to Conversions at 900 × 650 points in each system appearance, then capture the window at 2×; restore the original appearance afterward. They are not mockups. Asset sync copies these to `apps/site/public/images/settings-{light,dark}.png`; the README uses the same source pair. Historical captures remain dated evidence.

`social/og.png` is a designed Air 1.7.5 card, not an app screenshot. Its configuration is `artwork/social.json`; the full shared template and renderer are in `docs/air`. Build the site, run `node docs/air/render-social.mjs` with the documented browser-authoring dependency, rebuild and run website verification. The initial November 17 card was captured through the host’s approved browser-control tool using that exact template, light appearance, reduced motion, a 2× settled-artwork crop and a 1× 1200 × 630 PNG export. Browser layout evidence accompanies the Air audit.
