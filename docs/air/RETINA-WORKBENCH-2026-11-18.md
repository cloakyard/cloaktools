# Finder Workbench screenshot review

The local website shows the Finder Tools Workbench from CloakTools 0.6.0 Beta (20261118.4) in light and dark appearances. Both native captures measure 2000 × 1400 pixels. Each screenshot includes the branded sidebar, search field, tool categories and Settings button. The tool list contains no user files or clipboard data.

[Light Workbench capture](../../assets/screenshots/workbench-light.png) · [Dark Workbench capture](../../assets/screenshots/workbench-dark.png)

Chrome loaded the expected image at 390, 820, 1280 and 1600 CSS pixels in each appearance. The eight layouts preserved the native aspect ratio and had no horizontal overflow. The seven built routes passed link, anchor, contents, metadata and shared layout checks. Across those routes, link conformance passed 1080 layout/state checks and 428 keyboard checks. The worker dry run passed.

On macOS 27.2.1 the 44-point sidebar icon used its dedicated 88-pixel Retina rendition. Both appearances were captured and inspected at 4×. The installed Workbench opened all seven Settings tabs, including Privacy and About. Check for Updates contacted the live feed and displayed the native up-to-date dialog. The Developer Tools category opened JSON controls and the sidebar returned to Finder Tools. All 233 core and 19 hosted tests passed. The verified DMG matched 137 installed bundle entries. This review covered local browser and native UI behavior. Public release, spoken VoiceOver and Developer ID distribution await separate verification.
