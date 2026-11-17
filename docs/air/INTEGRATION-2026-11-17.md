# CloakTools family integration verification

November 17, 2026. Scope: all seven website routes, repository conventions, and
the native About support link. This follows the earlier same-day website audit;
its historical observations are preserved. The app remains a development preview.

## Changes

- Registered CloakTools with Cloakyard's generator and family public-page,
  privacy, artwork and README checks. Root and website `DESIGN.md` now use the
  same generated full contract and portable bundle schema as the other products.
  The complete previous native guidance is preserved in `NATIVE_DESIGN.md`.
- Adopted the shared integrity/portability checks and source inventory format.
  The reference gallery is authoring material, never a production dependency;
  the static build remains independent of sibling checkouts.
- Added the family Ko-fi destination to native About with a system Link and
  cup-and-saucer symbol, plus `.github/FUNDING.yml`. No widget or automatic request.
- Checked in the existing Cloudflare custom domain and static 404 configuration,
  pinned Wrangler/Node, and added website CI with verification, dry-run and Knip.
- Updated stale hosting and native-design references, repository guidance and
  release wording. Public installers remain unavailable; a web deploy does not
  publish a native release.
- Removed unused `Arrow.astro`, unused reading-table CSS and the redundant old
  contract copy. Kept `Reading.astro`: Markdown frontmatter uses it, so the Knip
  configuration names that real entry instead of suppressing unused-file checks.
- Isolated decorative paper and native screenshot geometry in `artwork.css`.
  The canonical Air CSS is byte-identical. Fixed the missing `install-title`
  target and added validation for dangling ARIA references.

## Per-view coverage

Chrome/macOS through the supported computer-use browser. All rows below include
light/dark at 320×568, 375×812, 390×844, 430×932, 844×390, 768×1024, 1024×768,
1280×720, 1366×768, 1440×900 and 1920×1080. Coarse input was emulated through
tablet widths; laptop/desktop used fine input. Screenshots are in
[`evidence/integration-2026-11-17`](evidence/integration-2026-11-17).

| View | Coverage |
| --- | --- |
| Home | Hero, finite/static artwork, actions, real native preview, feature groups, privacy, build guidance, footer |
| Install | Reading shell, complete contents, command examples, native limitations and return navigation |
| Privacy | Policy title/date, contents, prose, current Privacy footer and home return |
| Support | Long troubleshooting prose, contents and navigation |
| Source | Roadmap, repository destinations, reading composition and inline links |
| License | Complete legal copy and shared reading shell |
| 404 | Noindex, useful home action, shared header/footer and static recovery layout |
| Navigation states | Compact menu open/closed; Enter/Escape and focus return; 44px menu rows; contents anchors update hash and focus the heading |
| Native About | Rebuilt app; visible native support action; AX URL is exactly `https://ko-fi.com/sumitsahoo21` |

Measured results:

- **154 route/theme/viewport samples** with no document overflow, clipped tested
  text/controls, dangling ARIA references, broken eager images or unnamed actions.
- **56 enlarged-text samples**: every route, both themes, 320/390/768/1440px with
  200% root font. This is text reflow, not a fresh claim of actual browser zoom.
- **28 fallback samples**: all routes at phone and desktop widths in forced
  colors and with JavaScript disabled. Native menu expansion and Product anchor
  navigation were also exercised with scripts disabled. An initial locator
  timeout was resolved using the documented browser viewport control and native
  accessibility actions; the successful retry is the acceptance result.
- **500 visible links** across Tools/Yard home/reading routes checked in normal
  and focused states; **586 anchors** checked with the browser's hover pseudo
  state. Every observed color is neutral. Includes inline prose, not just Source.
- **308 family reference samples**: seven sites × home/privacy × both themes ×
  eleven sizes. Tools and Yard used current local production builds; the other
  five used their live public sites. Footer geometry, typography, colors, padding
  and available primary button skins agree. PDF's footer computes `min-height:
  auto` instead of `0px`, with equal rendered height; no visual correction needed.
- The reference scan found an existing dangling `install-title` on CloakRoll's
  landing page. It is recorded in `family.json`; CloakTools' own equivalent is
  fixed. This task does not certify that unrelated reference as error-free.

## Checks and cleanup

Passed: native `./scripts/build-native.sh`; website `npm run verify` and
`npm run check:worker` under Node 26.13.1/npm 12.2.2; root README checks;
`npx --yes knip@6.45.1` for the Astro graph; shared Air integrity and 22 isolated
portability assertions. Astro reports zero errors/warnings/hints. Static checking
validates seven pages and 224 local links/assets/anchors. OG/Twitter use the same
1200×630 PNG on all routes. npm reports no known vulnerabilities in the installed
dependency tree. Wrangler dry-run succeeds with no application bindings.

The family README pass checks ten READMEs and 151 local references, using PDF's
clean published reference checkout because its active AI worktree has an older
README. That work is not a deployment target. Shared reference assets and native
system/Objective-C/App Intent entry points are deliberate consumers, not dead code
to delete based on a JavaScript-only scan. The native change builds successfully;
this is not a whole-native-program reachability proof.

## Deployment and limits

Existing Cloudflare Workers Builds is connected to `cloakyard/cloaktools`, `main`,
root `/apps/site`, build `npm ci && npm run verify`, deploy `npx wrangler deploy`.
The public custom domain is `tools.cloakyard.com`; workers.dev and preview URLs
remain disabled. Promote verified `dev` through a PR and follow the connected
production build. Release PR checks record the deployment result; verify live
HTML, assets, policy routes, social PNG bytes and a missing path's HTTP 404.

No web editor, batch/library workspace, file processing, progress, transactional
dialog or PWA notice exists in CloakTools' website. These are native workflows,
not missing web surfaces. Other apps' editors, standalone tools, libraries,
processing errors and PWA lifecycle are not re-certified by this public-site
comparison. Physical devices, Safari/Firefox and spoken screen-reader acceptance
remain untested in this run. Native signing, Finder/Shortcuts and all tool behavior
retain their previously documented gates. KERR was not changed.

Modern Web Guidance: `css` informed reuse of the exact shared assets and removal
of redundant source ("Be allergic to knowledge duplication."). Responsive checks
used `responsive-design`; no new platform API or polyfill was introduced.
