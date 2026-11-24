# Subtitle generation and translation

Checked the development build on Apple silicon with macOS 27.2.1 and Xcode 27.2 on 24 November 2026. The File menu and the Images, PDFs & Media category use the same native editor.

- In the built app, opened a synthetic English MP4, generated two captions, selected Spanish and Hindi together and exported three UTF-8 SRT files. An independent FFprobe read each as SubRip with identical start times of 0 and 3,960 milliseconds and durations of 1,740 and 1,440 milliseconds.
- Generated 44 cues from a two-minute WAV and translated them to Spanish. FFprobe read all 44 cues in both exported tracks with identical timing across the translation batch boundary.
- Opened a movie with a delayed audio track. Its first recognized cue began at 1.80 seconds on the movie timeline. Edited the first English caption from a blue train leaving at nine to a green train leaving at ten. The prior translations cleared. Retranslation produced “El tren verde sale a las diez.” Turning off the original left two translated tracks available for export.
- Used a movie without audio, then chose a different file from the same editor. A silent WAV returned a no-speech message. Cancelling recognition on a 30-minute WAV returned to the spoken-language picker and Generate Captions.
- Inspected the Workbench review visually and through macOS accessibility controls. Verified the language checkboxes, cue playback controls, native text editing, translated text beside its source, file chooser, completion state and Show in Finder control.
- The native build passed. All 251 core and 40 hosted tests passed. Subtitle-specific tests cover Unicode, SRT timing and cue order, invalid drafts, filename collisions, atomic publication, missing audio, cancelled translation replies and retrying a failed language while retaining completed ones.

The initial live translations used installed English, Spanish and Hindi models.

## Follow-up validation on 24 November 2026

- Completed and exported a 30-minute WAV through the app. FFprobe read 618 consecutive, nonoverlapping SubRip cues through 29:59.700. A separate 30:00.250 recording was rejected at the file limit, and the same editor accepted a replacement.
- Opened a stereo MP4 with synthetic speech and pink noise from Workbench search. One phrase, “two red apples,” was transcribed as “to red apples.” Corrected source text and edited the French translation through the native text fields. FFprobe confirmed identical timings across English, French, Japanese and Arabic (Saudi Arabia). Exported text retained the edits and scripts, and the source file's SHA-256 digest stayed the same.
- French (France) speech assets were initially absent. Used **Download & Generate** and verified that macOS then reported French as installed. Recognized French audio and exported only the English translation. The French recognizer also misheard part of the synthetic recording.
- Interrupted two-target translation after Spanish completed. Exported Spanish, retried French, and exported both to a numbered folder. The first folder and the reused Spanish SRT were byte-identical before and after the retry. Cancelling the destination chooser preserved the review for a later export.
- Cancelling before the first translation finished incorrectly reported that completed tracks were ready when the original was excluded. Corrected the notice, reproduced that scenario on the rebuilt app and verified that Retry Translation was available. A hosted regression test covers cancellation both before and after a track becomes exportable.
- Eight concurrent exports into the same destination produced distinct complete folders with matched language tracks and preserved an existing folder. The native build, all 252 core tests, all 41 hosted tests and the Air and README checks passed.

The tests ran on macOS 27.2.1 with Xcode 27.2. First-use translation model downloads, spoken VoiceOver and macOS 27.0 runtime acceptance remain unverified. Measuring recognition and translation accuracy would require recordings from more speakers and independent language review.

[Usage guide](../USAGE.md#generate-subtitles) · [Apple Speech timing](https://developer.apple.com/documentation/speech/speechtranscriber/preset) · [Apple Translation](https://developer.apple.com/documentation/translation/translationsession)
