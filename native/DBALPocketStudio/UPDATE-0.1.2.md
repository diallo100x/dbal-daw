# Pocket Studio 0.1.2 — waveform editing, sampler and XY performance

Full source update, with the previous compiler fixes, metronome/count-in, multi-clip selection and dedicated undo/redo controls included. Legacy still targets iPadOS 15.4; Pro and Mac Catalyst schemes remain available.

## Build and install

```bash
cd ~/Downloads/DBAL-Pocket-Studio-0.1.2
bash Scripts/build_unsigned_ipa.sh Legacy
```

Finder reveals `Build/PocketLegacy-0.1.2-unsigned.ipa` after a successful build. Use the same Sideloadly account and bundle-ID settings as your existing installation. Export sessions before updating; keep the existing app installed to retain its document store. This ZIP contains source, not a precompiled IPA.

## Waveform handles

Select an audio clip. Drag its cyan side handles inward to crop either end. Drag outward to restore audio up to the original file boundaries. Timeline snap applies to trim boundaries. Source audio stays intact; trim changes source offset and playable length.

Drag the orange upper corners inward to create fade-in or fade-out. Shift-click within a faded area to cycle Linear, Slow and Fast curves. Without a hardware keyboard, use Edit N Clips → Cycle Fade Curve. Curves are saved per clip and apply to both its fades. Each completed gesture creates one undo step. Fades are rendered into a replaceable playback cache; original files remain untouched.

## Simple sampler

Select an instrument track and open **Sampler / XY**. Choose Keyboard or Pad 1–8, then Import Sample. Importing applies that slot immediately and activates Sampler Keys or Sampler Pads. Edit the waveform using the same side/corner gestures, set root/loop/one-shot, then tap **Apply Crop / Fades**. Full File restores the sample boundaries. Curve cycles the fade shape. Play Applied auditions the committed settings.

Sampler Keys maps one sample across the piano at its selected root. Sampler Pads maps eight samples to GM notes 36, 38, 42, 46, 41, 45, 49 and 51. Unassigned pads use the bundled starter drum sounds. The four-by-two rectangular pad grid and piano generate notes for the selected track. Keyboard and pad assignments are retained together, but one sampler mode plays per track. Use separate tracks for simultaneous keyboard and drum instruments.

Samples and crop/fade settings travel in portable projects. Samples are downmixed to mono and loaded into RAM with the existing per-instrument budgets: 64 MiB Legacy, 256 MiB Pro. Crop short regions for the old iPad. Looping has no loop crossfade; choose a suitable region to avoid clicks.

## MIDI matrix and repeater

The MIDI panel generates internal note input for the selected instrument, including AUv3, SF2/SFZ and sampler instruments. Arm that track and Record to capture notes.

- Pitch matrix on: X selects −12 to +12 semitones, Y velocity; Root sets the base note. Pitch uses discrete MIDI notes even when Snap is off.
- Pitch matrix off: X selects repeater division, Y velocity. Enable Note repeater to repeat; the separate rate picker sets repeat speed when pitch mode is on.
- Repeater also affects held onscreen piano keys and drum pads. Its timing uses the existing main-run-loop scheduler and can jitter under load.
- Its own **Snap** checkbox sits at the matrix's upper-right. Note repeat aligns to transport subdivisions when snapping during playback.

MIDI performance controls are live controls, not saved gesture automation. There is no external CoreMIDI output in this release.

## Separate audio FX matrix

Enable Audio XY on the selected track. It processes that track's playback before third-party inserts. Enabling/disabling rebuilds the graph and stops transport; moving the matrix or changing effect mode does not rebuild the graph.

| Mode | X | Y |
| --- | --- | --- |
| Pitch | −12 to +12 semitones | Fine pitch ±50 cents with Snap off |
| Repeater | Capture/repeat division | Wet mix |
| Filter | Low-pass cutoff | Wet mix |
| Wah | Tempo-synced filter sweep division | Wet mix |
| Gate | Tempo-synced gate division | Wet mix |
| Flange | Tempo-synced modulation division | Wet mix |

Tempo divisions span four beats through 1/64 note. The matrix has its own upper-right **Snap** checkbox, independent of timeline and MIDI snap. Repeater first captures a slice, then repeats it; changing division restarts capture. These are basic built-in effects, with no feedback controls or FX chaining inside the matrix. Pitch uses Apple's native time/pitch unit; other modes use the bundled C DSP.

Audio XY settings save with the project and participate in stereo export. Gestures are not recorded as automation. Raw microphone takes remain unprocessed, consistent with the existing recording path.

## Validation

Project generation/source membership and the portable sampler/XY DSP sanitizer tests passed here. Swift regression tests are included but could not run: this environment has no Swift compiler, Apple SDK or Xcode. The new Swift code, custom Audio Unit, gestures and hardware audio behavior need a Mac build and iPad test. The earlier release's successful recording does not validate these additions. See DEVICE-TESTS.md for the new checks.
