# Local packages and future releases

Version 0.6.0 targets Apple silicon and macOS 27+. Signing and notarization are deferred by the project owner, who does not currently have a paid Apple developer account. The local preview is usable without that account. Additional signed Finder folders and live Shortcuts execution are not supported by this ad-hoc package.

## Local preview

```sh
python3 scripts/release.py --preview --preflight
python3 scripts/release.py --preview
```

The script generates the normal XcodeGen project and builds Release serially into `apps/macos/build/PreviewRelease`. It verifies the app and embedded Finder extension with `codesign --verify --deep --strict`, checks version/build agreement and arm64 architecture, and writes a new timestamped directory under `apps/macos/build/Packages` containing:

- `CloakTools-0.6.0-local-preview.zip`
- `SHA256SUMS` and `manifest.json`
- `README.txt` and the build log

An explicit `--output /absolute/new/directory` is supported; an existing output directory is rejected. This is an ad-hoc development package, not a Gatekeeper-approved public installer. No signing or notarization upload occurs in preview mode. Build and test jobs should not run concurrently against the same generated Xcode project.

Quit an older CloakTools copy before replacing it. Keep a single intended installed copy for normal use; Launch Services may otherwise select another build. Settings → About offers signed updates and opt-in automatic checks. Before uninstalling, restore any CloakTools web/email defaults through Open With and review saved app data separately. Removing the app does not remove generated files.

## Developer ID path, for later

Prerequisites are a valid Developer ID Application identity in the current keychain, its actual team ID, and a supported shared app-group configuration. The project contains no personal team ID, copied certificate, password or API key. Do not add an invented entitlement to make an ad-hoc build appear signed.

```sh
python3 scripts/release.py --preflight \
  --team YOURTEAMID \
  --identity 'Developer ID Application: Your Name (YOURTEAMID)'

python3 scripts/release.py \
  --team YOURTEAMID \
  --identity 'Developer ID Application: Your Name (YOURTEAMID)'
```

These placeholders must be replaced with actual matching credentials. The signed path uses `apps/macos/project-release.yml`, hardened runtime, timestamped signatures and matching team-prefixed app-group entitlements. It verifies the actual signature team/group/runtime and rejects a debug get-task-allow entitlement. A signed package without notarization is still not a completed public release.

After explicitly choosing to submit the app to Apple, use an already-configured `notarytool` keychain profile:

```sh
python3 scripts/release.py \
  --team YOURTEAMID \
  --identity 'Developer ID Application: Your Name (YOURTEAMID)' \
  --notarize --notary-profile CLOAKTOOLS_NOTARY_PROFILE
```

Only `--notarize` submits an archive. It waits for Accepted, staples and validates the app, runs Gatekeeper assessment, then rebuilds the ZIP with the stapled app. No automatic publication follows. The manifest always records `publicRelease: false`; a human release decision follows the remaining checks.

## Acceptance before distribution

- Run core tests, hosted App Intent tests, native build and website verification. Follow [current evidence](verification/ROADMAP-IMPLEMENTATION.md).
- In a signed build, run all three actions from actual Shortcuts, including cold launch, cancellation, original filenames, downstream Quick Look/Save File and changed/hidden saved sets. Unit `perform()` tests and action discovery are not sufficient. The current ad-hoc run fails with LinkDaemon.ProcessRegistry error 0 and missing team identity.
- Exercise the complete [Finder scope matrix](FINDER-ACCESS.md), including actual bookmark transfer, multiple extension instances, remove/renew, stale/missing folders, host/Finder restarts, install/update/uninstall and privacy revocation. The entitlement gate passing alone is not access validation.
- Verify supported minimum macOS, spoken VoiceOver, minimum window sizes/long labels, broader file-provider/codec/performance cases and actual Edge routing before advertising them. Browser profiles are not shipped.
- Extract the final archive into a fresh verification directory, compare its checksum, verify the extracted signature and launch that exact package. Repeat default-handler restoration before uninstalling a test build.

No public repository, download, DNS deployment or website hosting action is part of this local package command.
