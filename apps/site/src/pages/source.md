---
layout: ../layouts/Reading.astro
title: Source
description: A small native core, a thin app, and an independent website.
---
## Source is available

The [CloakTools source repository](https://github.com/cloakyard/cloaktools) includes the native app, this website, build instructions and verification records. A public installer is not available yet; follow the [build guide](/install/) to try the development preview.

The app is written in Swift using SwiftUI, AppKit, FinderSync, Core Image, ImageIO, Vision, PDFKit and AVFoundation/AVKit. It includes no third-party Swift dependencies, browser engine, bundled language runtime, or cloud rules service. The website is a separate static Astro build using a pinned local copy of **Cloakyard Air 1.7.5**.

## Project structure

- `apps/macos/App` — native settings, operations, chooser, URL and Services entry points.
- `apps/macos/FinderExtension` — bounded Finder menus and host handoff.
- `apps/macos/Packages/CloakToolsCore` — preferences, templates, safe output, native conversion, and routing models.
- `apps/site` — this independently buildable website.
- `docs` — architecture decisions, roadmap, and recorded verification.

## Roadmap

**MVP 0:** native settings, a representative template catalog, one image-conversion direction, a real incoming-link chooser, and this website foundation.

**Milestone 1, in progress:** valid blank JSON/PDF, imported text templates, favorites, default naming, optional opening, clipboard text/image creation and native image conversion, PDF assembly and Copy As are available now. The Finder access review is documented; configurable scopes are implemented behind supported app-group signing, with signed runtime validation deferred. Broader permission and lifecycle coverage remains open.

**Milestone 2, in progress:** ordered web/email rules, compatible app selection, an offline link tester, explicit one-time bypass and explanatory fallback are available. Independent default-handler setup and guarded restoration are also available. Pinned app order, availability feedback and separate web/email fallback choices are also available. Verified Edge/profile routing remains open. The first public beta follows these two milestones.

**Milestone 3, in progress:** Make It Fit previews native image output against format, dimensions and a byte budget, then saves the exact measured copy. Organize PDF now includes page selection, ranges, order, rotation and safe copy export. Full-clip MP4 and M4A exports now include native playback, capability checks and cancellation. Existing conversion tools are grouped behind expandable rows; further work must add a concrete workflow benefit beyond macOS.

**Milestone 4, in progress:** folder presets save a destination, file type or template, name and blank-code preference. Related file sets and reusable folder templates now review nested paths and exact prepared content, then create one new folder without merging existing folders. Reusable image, fit and media recipes now save output settings, with fresh-source review and explicit export. Sample Files now generates synthetic JSON/CSV records and exact-size text/binary files, with a preview before saving. Example Copy now prepares JSON and environment placeholders with source/example comparison and explicit safe saving. Markdown Digest now combines explicitly selected text files with ordering, file/digest review and safe Markdown copies. Three Shortcuts actions are implemented for image fitting, Markdown digests and saved-file-set review. They are discoverable, but live execution remains signing-gated in the ad-hoc preview. Project archives are deferred pending a clear benefit beyond Finder Compress.

**Milestone 5, in progress:** everyday Text Cleanup, File List and QR creation/reading are available. File List exports reviewed CSV/Markdown metadata. QR creation turns explicit text or links into previewed PNG images, with image sizes, correction choices and safe saving. QR reading adds selected-image review, numbered code locations and safe decoded-text export in the same workspace. Standalone OCR and other basic utilities already supplied by macOS are excluded from future work.

## Build on what macOS does well

Preview already [copies text from images with Live Text](https://support.apple.com/en-gb/guide/preview/prvw625a5b2c/11.0/mac/27). Finder handles [batch renaming](https://support.apple.com/guide/mac-help/rename-files-folders-and-disks-on-mac-mchlp1144/27/mac/27) and [ZIP archives](https://support.apple.com/guide/mac-help/zip-and-unzip-files-and-folders-on-mac-mchlp2528/mac). These do not need another CloakTools dialog. A standalone Keep Awake tool and general file inspector are also outside the active roadmap.

Existing image, PDF, clipboard and QR creation tools overlap with native capabilities. They remain available in compact secondary groups, alongside the same saved workflows and keyboard shortcuts. The focus is measured image byte budgets, reusable file sets, reviewed structured exports and routing across apps. Future features must add a clear benefit beyond the built-in workflow, and automation should integrate with Shortcuts.

The local repository includes the full macOS feature audit and the revised roadmap. The 0.6.0 preview adds safer staging and media recovery, conservative event-source handling, automation integration and a verified local ZIP pipeline. Signing is deferred; no new general-purpose utility is queued automatically.

## License and contributions

CloakTools uses the [MIT License](/license/). Contributions should include focused verification and preserve user files. Native app and website checks are independent. See the repository’s contribution and security documents before submitting a change.

The 0.6.0 verification passed 224 core tests and 8 hosted app tests. Live checks cover light/dark and contrast/transparency layouts, reduced-motion navigation, keyboard-driven image fitting, Shortcuts action discovery and exact link delivery. All tested system settings were restored. Shortcuts execution is blocked by the ad-hoc signing identity; signed Finder-folder checks and notarization are deferred. Spoken VoiceOver, macOS 27.0 and broader installer/filesystem/codec checks remain open. Updates are manual; no automatic updater or public installer is provided.
