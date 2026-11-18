# Structured QR codes

Verified the ad-hoc signed development build on Apple silicon with macOS 27.2.1 on 18 November 2026. The published 0.6.0 beta predates the structured forms.

## Workbench review

| Workflow | Observation |
| --- | --- |
| Create and read a guest Wi-Fi code | From Text & Sharing, selected Wi-Fi, entered a network name containing a semicolon and a sample password, and saved a 512-pixel PNG. Read identified the network and concealed its details. Show encoded text displayed the escaped name and the original password. |
| Share a contact | Generated a contact card, saved the PNG, opened it in Read and saved the decoded card as a .vcf. The file contained the entered first and last names. |
| Share an event | Generated an event, saved its PNG, read it back and chose Calendar (.ics). Save Calendar File produced Calendar event.ics with the entered title, a UID and UTC start and end times one hour apart. |
| Edit a draft | Switched between contact and event forms. Returning to the contact restored the entered fields and cleared the previous type’s preview. Reviewed forms in light and dark appearance. An unchanged field commit during generation now retains the prepared image. |

## Automated checks

The native host and Finder extension built successfully. All 240 core and 21 hosted tests passed. The suite creates, saves and decodes a PNG for each of the nine types and compares the decoded UTF-8 bytes. Apple’s Contacts parser also recovered escaped names and organization data from a folded Unicode vCard. Other checks cover reserved characters, UTC event times, coordinate limits, encoded size, native document exports and preview invalidation.

Scanner coverage here uses macOS Vision and Core Image. Physical iPhone and Android scans, print quality, and joining a real network remain unverified.
