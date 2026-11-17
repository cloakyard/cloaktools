# Contributing

Keep native domain work in CloakToolsCore, UI state in the host, and Finder callbacks thin. Prefer public system frameworks and avoid new runtime dependencies without a concrete need. Preserve user files, keep output publication exclusive, and test the real integration affected by a change.

Run `./scripts/build-native.sh`, core `GIT_CONFIG_COUNT=0 swift test`, and `npm run verify` in `apps/site` for affected surfaces. See README for exact directories. Record failures and manual gates honestly in `docs/verification`. Do not treat unit tests as Finder/URL/UI acceptance.

Use semantic native components, SF Symbols and system materials. Read NATIVE_DESIGN.md before native changes and DESIGN.md before website work; pinned Air assets must not be silently edited. Keep website and native privacy/status claims synchronized. Reference repositories are read-only. Do not commit generated projects/builds, binaries, node_modules, personal fixtures, sensitive screenshots or logs.

Use `dev` for changes and promote verified work to `main`. The repository is https://github.com/cloakyard/cloaktools; keep only these two maintained branches. Website deployment and native releases are separate, explicit actions. Contributions use the MIT License. Do not add co-author trailers to commits.
