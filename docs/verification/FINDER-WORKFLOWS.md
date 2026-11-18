# Finder workflows and beta Settings

Verified on 18 November 2026 on Apple silicon running macOS 27.2.1. This record covers the source Workbench. The published 0.6.0 installer predates these additions.

## Finder and Workbench

| Workflow | Observed result |
| --- | --- |
| Make It Fit | From Finder, a selected PNG opened directly in the image editor. Entering “under 2 MB” and pressing Preview Fit showed both images and a measured 17,287 bytes. Saving created a 17,287-byte JPEG beside the original. A second save used an available numbered name. Right-click → Services also passed the selected photo to the editor. |
| Reuse Folder Structure | The preview showed Assets with its Photos child, Briefs and Deliverables. After deselecting Briefs, Create Folder produced only Assets/Photos and Deliverables inside the new folder. Both leaf folders were empty. Hosted tests also saved and updated the selected branches through the review, using a temporary file-set library. A core test reopened the stored definition and created its structure through the existing file-set engine. |
| Collect Copies for Sharing | Invoked the Service on two identically named receipts in different Finder windows. The collection showed both source paths and proposed Receipt.txt and Receipt 2.txt. Save Copies opened the destination picker. Both files in the resulting folder matched their respective sources byte for byte. |
| Compare Two Folders | A five-difference fixture included items on either side and a same-name, same-length receipt with different contents. The review distinguished all three cases. Reveal selected the file in the indicated Finder folder. A subsequent scan included Finder’s hidden .DS_Store files. A second request could open in an independent window. |
| Return to an open collection | Launch Services sent two selection URLs to the unmodified development host using the same NSWorkspace call as Finder Sync. A second selection appended to the first. A first pass exposed a SwiftUI scene replacement that discarded drafts on URL delivery. The Workbench now accepts incoming URLs in the open scene. A hosted regression test sends two Get URL Apple events to the application. An ordinary loopback HTTP URL still opened the link chooser. A cold-start Finder URL also opened the selected photo in Make It Fit. |

The installed public beta and development build share a bundle identifier. To exercise the new Services alongside the installed app, the test registered a temporary copy of the built executable with a separate bundle identifier, service port and app name. The four new Services retained their configured names, file type declarations and selectors. The temporary provider was unregistered after testing. Finder offered image fitting for a PNG, collection for regular files, and the folder actions for directories.

Settings reported the scoped Finder extension as disabled, and its top-level items were absent from the workspace context menu. The selection rules were tested in code and the host handoff ran live. Direct invocation from an enabled Finder Sync menu, external or network volumes, and spoken VoiceOver remain outside this run.

## Settings audit

CloakDrop’s About header receives the bundle version and build. CloakRoll adds its bundle release channel to the same version line and sets Beta in its release configuration. CloakTools uses this version-line placement and sets Beta in its normal project configuration and its release configuration. The normal debug app displayed **Version 0.6.0 (20261118.2) · Beta**. Its signature was ad hoc. The audit covered the sibling apps’ local source and the running CloakTools About panel.

The four review screens were inspected in light appearance, with additional dark checks for comparison and Settings. The Finder Settings tab lists the registered Service names and the selection each accepts.

## Automated checks

- The native build script built the macOS host and embedded Finder extension.
- 233 core tests passed. Coverage includes filtering directories and links, nested selection, file-set round trips, copy-name conflicts, changed-source rollback, equal-size content differences, resource forks, hidden files, symlink loops and cancellation.
- 19 hosted tests passed. Coverage includes exact byte-limit parsing, repeated Finder selections, collection while saving, branch selection and updates, Service selectors, the About channel, and the existing Workbench and automation tests.
- The Air design, portability and README checks passed. The site verification checked seven routes, and the worker dry run passed.
