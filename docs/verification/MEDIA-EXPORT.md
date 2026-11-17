# Native media export verification

Verified 15 November 2026 on macOS 27.2.1 (26B131), Apple silicon, Xcode 27.2 / macOS 27.2 SDK / Swift 6.4.2. Native development preview **0.3.2 (12)**. This is local development evidence, not a public-release claim.

## Working path

**File → Export Media… (⌥⌘E)**, General Quick Actions and Conversions → Media Export accept one local movie or audio file. The compact editor offers native playback without autoplay, source duration/dimensions, only compatible output presets, a filename and destination. MP4 presets use H.264 at up to 720p or 1080p with AAC audio when present. M4A exports AAC audio only. Exports include the full clip, keep orientation and do not enlarge smaller video. Native progress and cancellation remain visible outside the scrolling content. Saved copies offer Finder reveal and explicit QuickTime opening.

The operation captures the source once into a private temporary directory (0700; source file 0600), streams the copy in bounded chunks, checks for ordinary concurrent source changes and forbids external media references. Playback and export use that same capture. Export builds a composition containing only the selected video/audio tracks, validates the output, then publishes with exclusive rename and numbered collision handling. Source metadata is not copied. Normal cancellation removes unfinished destination staging; closing the operation releases its private capture. No dedicated Finder menu or Service was added in this slice.

## Automated checks

```sh
GIT_CONFIG_COUNT=0 swift test --package-path apps/macos/Packages/CloakToolsCore
GIT_CONFIG_COUNT=0 ./scripts/build-native.sh
npm --prefix apps/site run verify
```

- **105 tests passed**, including eight new media tests covering capture permissions/lifetime, source changes/deletion after capture, M4A collision handling and decoded audio, H.264/HEVC portrait orientation, both MP4 presets, audio extraction, metadata omission, 1080p reduction to 720p, progress bounds, multiple-audio-track rejection, AAC input, invalid inputs/options/folders and pre-cancelled work. Existing file, image, PDF and routing checks also pass. [Core log](media-core.txt).
- Native Debug arm64 build: **BUILD SUCCEEDED**, no Swift warnings. Expected unused AppIntents metadata warning and ad-hoc hardened-runtime notes remain. Bundle reports **0.3.2 / 12**. [Build summary](media-build.txt).
- Website: **7 routes**, zero errors/warnings/hints; local links/assets, canonical metadata, landmarks and pinned Air hashes pass. [Site log](media-site.txt).
- A separate native-core matrix exercised **12 export directions** across MP3, AIFF, CAF, WAV, MP4, H.264 MOV with audio and rotated HEVC MOV. All succeeded. All 12 matrix outputs and both live-app outputs decoded independently with FFmpeg without errors. FFprobe confirmed H.264/AAC tracks, expected dimensions and durations. [Matrix](media-matrix.txt), [decoded output and source hashes](media-output.txt).

## Actual native interaction

Fixtures were generated from synthetic graphics and a sine wave using [the native fixture script](../../scripts/make-media-verification-fixtures.sh). Existing FFmpeg was used only to generate MP3/AIFF/CAF variants and independently verify outputs; it is not an application dependency. No personal media was used.

1. Opened **Motion and tone.mov** through the new command: 12 seconds, 1920 × 1080 at 30 fps, 3,443,955 bytes. The preview showed all three supported outputs and did not autoplay. Explicit Play advanced the native timeline.
2. Started an export and immediately cancelled with Escape. The editor reported cancellation; no final file or staging directory remained. Retried successfully and observed measured progress at **53%** with editing disabled and Cancel still available.
3. Exported **Motion 720.mp4**: **1,263,351 bytes**, H.264 1280 × 720 plus mono 48 kHz AAC, 12.000 seconds. Open in QuickTime worked and the playback timeline advanced past seven seconds.
4. Exported **Motion audio.m4a**: **302,466 bytes**, mono 48 kHz AAC with no video. QuickTime opened it and playback was invoked. AVFoundation/QuickTime show 12 seconds; FFprobe reports a 12.053333-second container, reflecting AAC padding. Audio decoding and signal checks pass; no claim of subjective listening quality is made.
5. A live cleanup check exposed a window-close lifecycle issue: Done bypassed `windowShouldClose`, retaining the source capture through the player. Cleanup now also runs in `windowWillClose`. Repeated the completed-export close and confirmed its private capture was removed. The verified synthetic capture left by the earlier build was also removed.
6. Opened **Tone.wav** in DEBUG light appearance. The audio-only window reduced to **480 × 440 pt**, exposed only M4A and retained visible name/destination/actions. Cancel dismissed the unsaved draft. Normal app launch/appearance was restored; no private media captures remained. QuickTime test windows were closed. Web defaults remain Google Chrome and email remains Mail.
7. SHA-256 hashes of all four original native fixtures remained unchanged. Independent decoding confirms that portrait HEVC exports are 720 × 1280 in both presets, and a 720p source is not enlarged by the 1080p preset.

Screenshots: [dark video editor](../../assets/screenshots/media-export-dark.png), [compact light audio editor](../../assets/screenshots/media-audio-light.png), [output in QuickTime](../../assets/screenshots/media-quicktime.png).

## Design and website review

Video starts at **480 × 550 pt**; audio at **480 × 440 pt**, with a 440 × 440 pt minimum. System player controls sit in a restrained preview card; the existing Liquid Glass/accessibility-aware footer holds the primary action. Destination, progress, errors and output feedback remain native. External playback and sharing/Picture in Picture controls are disabled. All decoding/encoding and file capture run away from the main actor.

Home, Install, Support, Source and Privacy copy describe the capability and limits while preserving the Cloakyard Air shell and app-specific animation. Install was visually reviewed at **1728 px** and **320 px**, and Support at **320 px**. Both narrow pages had `scrollWidth === innerWidth`, readable wrapping and no horizontal overflow. [Desktop guide](../../assets/screenshots/media-site-desktop.jpg). The viewport override was reset, the test tab closed and the local development server stopped. Nothing was published.

## Boundaries and remaining checks

- One self-contained file, up to 1 GB and 30 minutes. SDR H.264/HEVC video up to a 4096 × 2160 bounding box in either orientation at 60 fps; AAC/MP3/PCM audio with one or two channels up to 96 kHz. One video track and at most one audio track, or audio only. Actual native compatibility determines the offered presets. M4V is accepted by extension but was not separately exercised in the container matrix.
- Protected, HDR/wide-gamut, alpha and spatial media are rejected. Chapters, subtitles and source metadata are omitted; visible/audible content remains. No trimming, target-size guarantee, metadata anonymization or general codec conversion is claimed. Encoders can add their own technical metadata and audio padding.
- Output is capped at 2 GB **after** encoding. Native work can use additional memory and disk. Abrupt termination can leave private source or destination staging files; crash recovery is not implemented. Full 1 GB/30-minute/4K loads, actual HDR/spatial assets, unusual transforms/timelines, disk-full/provider failures and adversarial media need broader testing before release.
- Live cancellation covered a normal in-flight export, and automated checks cover pre-cancellation and exclusive publication. Every possible cancellation/publication race was not exercised. The successful final rename wins if a late cancellation arrives afterward.
- Actual VoiceOver/Reduce Transparency/increased-contrast interaction and minimum-size/long-label stress were not exhaustively tested. Shared controls retain their existing accessibility adaptations.
- Verification used the Debug ad-hoc build. Developer ID signing, notarization, installer/update lifecycle, supported App Group Finder scopes, Edge/profile routing and the earlier release gates remain open.

## API references

Implementation was checked against the installed macOS 27.2 AVFoundation/AVKit headers and interfaces, including the async [export API](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession/export(to:as:isolation:)), [export states](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession/states(updateInterval:)) and native [1080p preset](https://developer.apple.com/documentation/avfoundation/avassetexportpreset1920x1080). No third-party media runtime was added.
