# Clop replacement on macOS

Reference installation reviewed on 23 November 2026: Clop 3.7.6, bundle identifier `com.lowtechguys.Clop`. The feature inventory draws on the installed bundle’s document and Service declarations, its ten App Intent definitions, CLI command help, its pipeline step reference and the [publisher’s feature guide](https://lowtechguys.com/clop/). Tests use generated media. The public CloakTools beta predates this work.

The acceptance target is standalone operation after removing Clop, including existing CloakTools workflows. Internet share links are excluded at the maintainer’s request. A similar control or successful compilation alone does not establish parity. Removal of Clop remains gated on the outstanding workflows below.

| Workflow in the reference app | Development build | Outstanding acceptance |
| --- | --- | --- |
| Mixed batch optimization | Workbench, menu bar, drop target and Finder Service use the same review. Per-item results, measured sizes, Quick Look, cancellation and collision-safe copies. | Very large jobs, folder input, remaining codecs and full comparison against reference outputs. |
| Clipboard | Explicit paste of local file URLs or an image. Optional optimization of new clipboard images checks pasteboard generation and excludes marked confidential, transient and generated items. | Global shortcuts, clipboard source/type rules, Photos full-resolution handling and more clipboard representations. |
| Watched folders and screen recordings | One opt-in folder. New stable files produce smaller copies in a subfolder. Pre-existing files establish the baseline. | Multiple per-type watches, recursive filters, per-folder pipelines and screenshot-specific triggers. |
| Still images | PNG, JPEG, HEIC, AVIF and WebP output. Native ImageIO decoding also accepts single-frame GIF, BMP, WebP and JPEG XL. Crop, scale and measured byte limits. WebP offers lossless encoding of the prepared pixels. | JPEG XL output and reversible JPEG transcoding, smart crop, custom geometry, watermarking, Retina resolution rules and dedicated lossless source-container metadata editing. |
| Animated images | GIF and animated WebP can produce GIF copies. Output retains frame count and reads frame delays and loop metadata. | Animated WebP output, wider animation matrix and perceptual compression comparisons. |
| Video | H.264 MP4 and bounded animated GIF export, scaled crops, rotation handling, speed and mute. Standard and stronger presets. | HEVC output, software x265, VP9/WebM, AV1/MKV, wider demuxer/codec coverage and per-codec controls. |
| Audio | AAC, WAV, AIFF and FLAC output, AAC bitrate controls, peak normalization and measured output sizes. | MP3/OGG output, loudness targets in LUFS, multichannel coverage and adaptive bitrate comparisons. |
| PDF | Screen-image optimization, optional JPEG compression, centered crop boxes and restore-to-media-box. Original files, normal page content and text are retained. Existing protections for signed or restricted documents apply. | MRC scanned-text compression, selectable DPI, device/paper presets, page padding, page image export and iterative target sizing. |
| Results and originals | Quick Look, copy image, reveal saved file, explicit same-format replacement with an adjacent recoverable original, restore, and optional Trash after a separately verified save. | Floating result shelf, global shortcuts, batch undo, backup management across launches and drag-out workflows. |
| Presets and pipelines | Named optimization recipes reuse settings from the menu bar and CLI. | Ordered conditional workflows, watermark and fork steps, preset drop zones, script/Shortcut handoffs, filename templates and third-party shelf integrations. |
| Automation interfaces | Bundled `cloakopt` supports batches, size limits, recipes and JSON-lines results. Finder Service and Optimize Media File App Intent. | Live signed Shortcuts execution, download-and-optimize, advanced CLI commands, settings and pipeline management, MCP tool interface. |

## Verification

Core fixtures cover decoded output types and dimensions, exact measured bytes, changed or removed sources, numbered collisions, duplicate restore attempts, rejecting changes to original files, PDF crop/uncrop, rotated moving images, changed duration, audio removal, GIF frames, common audio formats and stable-folder selection. Hosted tests cover named pasteboards and the Workbench batch lifecycle.

In the running development Workbench, a 2000 × 1400 repository screenshot measured 313 KB before preview and 145 KB at 50% scale. The review exposed Quick Look and Save 1 Copy. This is one fixture, and compression savings depend on its content.

The native app, Finder extension and bundled CLI built with Xcode 27.2 on macOS 27.2.1. All 246 core and 25 hosted tests passed. The bundled CLI also measured a 312,921-byte repository image at 96,171 bytes with a 100 KB limit. The named-pasteboard test exercised automatic replacement without touching the system clipboard. End-to-end LinkDaemon execution requires a team-signed build.
