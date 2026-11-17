# CloakTools contributor instructions

Read `CONTRIBUTING.md` and `README.md` for architecture and commands. Read
`DESIGN.md` before visible website changes and `NATIVE_DESIGN.md` before native
UI changes. Air governs the website; the Mac app keeps native SwiftUI controls,
SF Symbols and system materials.

The canonical web contract is maintained in `cloakyard/cloakyard` under
`design/air/`. Generated contracts and bundles are pinned here; standalone builds
must never require a sibling checkout. Run `node scripts/check-air-design.mjs`,
`node scripts/check-air-portability.mjs` and `node scripts/check-readmes.mjs`.

Website changes also require `npm --prefix apps/site run verify` and
`npm --prefix apps/site run check:worker`. Compare all seven public routes,
navigation/contents states, phone/tablet/laptop/desktop, light/dark, keyboard,
touch, enlarged text and static-motion fallbacks. Record coverage and limits in
`docs/air/`; website checks do not certify native tools or accessibility.

Build affected native changes with `./scripts/build-native.sh` and inspect the
changed UI. Run feature tests for changed behavior. Keep source/release claims
truthful: the app remains a development preview without a public installer.

Use `dev`, commit only verified bounded changes, then promote to `main` for an
authorized website deployment. Do not add co-author trailers or change KERR.
