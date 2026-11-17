# CloakTools website

**Small tasks. Less friction.** The independent Air companion to CloakTools.

[Website](https://tools.cloakyard.com/) · [Source](https://github.com/cloakyard/cloaktools) · [Product README](../../README.md)

## Overview

A static Astro website for the native Mac toolkit. The canonical address is reserved in metadata; hosting and DNS deployment are pending.

## Features

Home, Install, Privacy, Support, Source, License and a custom 404 page share Air navigation, typography and footers. Reading pages have native contents disclosures. The landing page has actual light/dark app captures and a finite, replayable document animation with a complete static fallback.

## Privacy

No accounts, analytics, cookies, remote fonts, service worker or runtime cloud dependency. Privacy content comes directly from [the root policy](../../PRIVACY.md). External links work only when chosen.

## Getting started

Use Node 26 or later and npm. From this directory:

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4321
# Stop Astro’s background development server:
npx astro dev stop
```

Open http://127.0.0.1:4321. See the [product README](../../README.md) for native setup; web commands do not build the Mac app.

## Development

```sh
npm run verify
node ../../scripts/check-readmes.mjs
```

Verification runs Astro diagnostics, builds seven routes, checks navigation/anchors/assets, complete reading contents, landmarks, metadata, pinned Air hashes and the shared OG image. Browser acceptance additionally covers every route at the Air viewport matrix, both themes, keyboard focus, native menu/contents behavior, zoom, reduced motion, forced colors and no JavaScript. The [dated audit](../../docs/air/AUDIT-2026-11-17.md) distinguishes measured checks from runtime limits.

## Design and assets

[DESIGN.md](DESIGN.md) contains the full Air 1.7.5 contract and product appendix. `src/styles/air.css` is unchanged upstream CSS; `global.css` holds product composition. [Bundle provenance](../../docs/air/bundle.json) pins upstream files by SHA-256. Neither build nor runtime reads sibling repositories.

`npm run sync:assets` derives the circular mark and copies canonical native captures and the OG card. See [asset sources](../../assets/README.md) and [social regeneration](../../docs/air/social-previews.md). Product-specific social content is in [artwork/social.json](../../artwork/social.json). Build first, render with `node ../../docs/air/render-social.mjs`, then rebuild and verify. The renderer requires an explicitly installed `puppeteer-core` or `PUPPETEER_MODULE` path and Chrome; these are authoring tools, not website dependencies. Automated browser tools must follow their host’s browser-use rules.

## Project structure

```text
src/components/   Shared header, footer, mark, contents and product artwork
src/layouts/      Document metadata, shell and reading layouts
src/pages/        Seven static routes
src/styles/       Pinned Air foundations and product composition
src/scripts/      Progressive navigation/focus enhancement
src/lib/          Trusted build-time reading-section formatting
public/           Synced brand, screenshots, OG card and robots file
scripts/          Static acceptance checks
```

## Deployment and releases

`npm run build` produces `dist`. Deployment has not been configured. Hosting must serve `404.html` with HTTP 404; do not use an all-routes 200 SPA fallback. Set up hosting only after the maintainer chooses the deployment target.

Maintain `dev` and `main`, promote verified changes together, and deploy the approved `main` revision. Native signing, installers and releases are separate from website publication.

## Contributing

Follow [the contribution guide](../../CONTRIBUTING.md) and local Air contract. Verify every applicable route and state; native test results do not certify website layouts. Preserve source truth for release availability, privacy and system requirements. This README follows the [family standard](https://github.com/cloakyard/cloakyard/blob/main/docs/README_STANDARD.md).

## License

[MIT](../../LICENSE). Shared Air files retain their upstream provenance; build dependencies retain their licenses.
