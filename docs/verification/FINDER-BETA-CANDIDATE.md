# Finder beta candidate verification

Tested CloakTools 0.6.0 Beta, build 20261118.5, on Apple silicon running macOS 27.2.1. The public feed and download continue to identify build 20261118.2.

## Finder and Workbench

| Check | Observed result |
| --- | --- |
| Selection filtering | Finder offered two candidate Services on a plain-text file: collection and list export. A PNG also offered Make It Fit and Read QR Code. A folder offered Folder Actions and list export. The candidate registers five typed Services. |
| Collect while browsing | Added a text file and a PNG in successive Finder Services invocations. Finder was frontmost after both. The menu-bar button announced two collected files. Clicking it opened a review with both source paths and editable copy names. |
| Compare | Selecting two folders opened a comparison with the differing receipt and its Finder reveal action. Starting with one folder offered Compare with Another Folder and a picker for the second folder. Confirming the picker compared the selected directories. |
| Read QR | Choosing the QR Service on the contact PNG opened the reader with the correct filename, one code and the vCard content type already identified. |
| Export file list | Invoking Copy or Export File List on two files, then choosing Export as CSV or Markdown, carried both items into the review. Preview Export produced a 92-byte CSV with the two filenames and their byte sizes. |
| File sets | A hosted test passed a selected folder directly to file-set creation. The editable review opened immediately and the destination remained empty until confirmation. |
| Workbench and website | Captured and inspected the final Finder Tools layout in light and dark appearances. The sidebar, all six actions and Settings fit within a 1000 × 700 point window. [Website checks](../air/FINDER-CANDIDATE-2026-11-18.md) |

The installed public product shares the development bundle identifier. Live Services checks used a temporary copy of the candidate host with a distinct bundle identifier, port and service-name suffix. The scoped Finder Sync entries did not appear in the live workspace context menu. Core tests cover their selection and URL rules. Enabled-extension acceptance on another Mac remains open.

## Build readiness

The Debug and Release configurations built. All 240 core tests and 23 hosted tests passed. Strict local signature verification passed for the Release host and extension. Both carry version 0.6.0, build 20261118.5, the Beta channel, an arm64 executable and an ad-hoc signature. The host uses the production feed URL, the configured Sparkle verification key and opt-in automatic checks. The dependency check found the pinned Sparkle and DMG tooling current.

This check covered source and local build products. Candidate packaging, installer acceptance, signing of distribution artifacts, and a real updater installation remain pending release authorization. Developer ID distribution and macOS 27.0 runtime acceptance remain unverified.
