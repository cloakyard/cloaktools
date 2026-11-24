# Subtitle generation and translation

Checked the development build on Apple silicon with macOS 27.2.1 and Xcode 27.2 on 24 November 2026. The File menu and the Images, PDFs & Media category use the same native editor.

- In the built app, opened a synthetic English MP4, generated two captions, selected Spanish and Hindi together and exported three UTF-8 SRT files. An independent FFprobe read each as SubRip with identical start times of 0 and 3,960 milliseconds and durations of 1,740 and 1,440 milliseconds.
- Generated 44 cues from a two-minute WAV and translated them to Spanish. FFprobe read all 44 cues in both exported tracks with identical timing across the translation batch boundary.
- Opened a movie with a delayed audio track. Its first recognized cue began at 1.80 seconds on the movie timeline. Edited the first English caption from a blue train leaving at nine to a green train leaving at ten. The prior translations cleared. Retranslation produced “El tren verde sale a las diez.” Turning off the original left two translated tracks available for export.
- Used a movie without audio, then chose a different file from the same editor. A silent WAV returned a no-speech message. Cancelling recognition on a 30-minute WAV returned to the spoken-language picker and Generate Captions.
- Inspected the Workbench review visually and through macOS accessibility controls. Verified the language checkboxes, cue playback controls, native text editing, translated text beside its source, file chooser, completion state and Show in Finder control.
- The native build passed. All 251 core and 40 hosted tests passed. Subtitle-specific tests cover Unicode, SRT timing and cue order, invalid drafts, filename collisions, atomic publication, missing audio, cancelled translation replies and retrying a failed language while retaining completed ones.

Live translations used installed English, Spanish and Hindi models. Fresh language downloads, other language pairs, noisy recordings, spoken VoiceOver and the macOS 27.0 runtime remain unverified.

[Usage guide](../USAGE.md#generate-subtitles) · [Apple Speech timing](https://developer.apple.com/documentation/speech/speechtranscriber/preset) · [Apple Translation](https://developer.apple.com/documentation/translation/translationsession)
