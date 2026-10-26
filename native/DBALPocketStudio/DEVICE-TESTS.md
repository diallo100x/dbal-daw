# Required Apple/device acceptance tests — not yet run

## Build and launch

- Build PocketLegacy Release for the physical iPad on iPadOS 15.4.1; record Xcode version, iPad model, RAM if known and negotiated sample rate/buffer.
- Build PocketPro on the newer iPad and one Mac Catalyst scheme. Confirm the complete timeline, transport, mixer strip and piano/pads remain accessible in landscape, portrait and a resized Mac window.
- Check denial/acceptance of microphone access; denial must not prevent instrument/audio-file playback. Apply Settings / Restart Audio after allowing access.

## A usable vocal session

- Import a 3–5 minute local beat. Verify waveform, correct duration and no initial clipping.
- Arm Vocals, choose wired headphones/interface, enable input monitoring if needed. Record a full verse. Check both channels as appropriate for the interface. Compare against the beat for alignment and dropouts.
- Repeat with click/pre-roll off, one bar and two bars at beat zero and at a later cursor. Audio and count-in must start together at the intended timeline beat.
- Stop once: cursor stays. Stop twice: zero. Seek via ruler. Move a clip with snap on/off and grids 1/4 through 1/32.
- Split at the cursor, trim start/end in Clip Editor, add fades, duplicate, delete, undo and redo. Compare source audio against exported output; original takes must remain intact.
- Play across a loop boundary several times. Start recording with loop enabled: capture must stay continuous instead of cycling.
- Play/record with the screen locked for at least five minutes. Test an interruption and unplug/replug the audio route; recovered session must remain saved and restartable.

## Instruments/plugins

- Play/record Starter Keys polyphonically; use pads with Starter Drums. Confirm a quick drum tap retains its one-shot tail and Stop clears hanging notes.
- Import a small known SF2. Select at least two programs and a percussion bank if present. Save/reopen and compare.
- Import a small folder-based SFZ with spaced filenames, inherited group settings, velocity layers and explicit loops. Confirm note range, tuning, pan and release. Test an unknown opcode and an escaped/absolute sample path; the former must warn, the latter must fail safely.
- Load a compatible DBAL AUv3 instrument (for example the iPadOS-15-compatible Instrument DNA build) and a compatible AUv3 effect. Play, open UI, change preset/parameters, save, relaunch and compare. Verify host tempo/meter/transport/loop context with a plugin that displays these values. No specific DBAL AUv3 has been tested with this host yet.
- Add two instances of the same effect with different settings. Save/reopen; settings must remain distinct. Try a missing plugin on another device: state remains, live playback warns, and mix export refuses silently incomplete rendering.

## Interchange and load

- Export a project, move it through Files to Pro and Mac, open it and verify recordings, MIDI notes, trims/fades, SF2/SFZ and plugin states. Match platform plugin installations; do not assume iPad binaries work on Mac.
- Export WAV, audition outside the app, verify 24-bit stereo, timing and fades. Test an instrument-only session and an audio-only session. Check reverb tails near the fixed two-second end.
- Add up to eight representative tracks on the older iPad, then increase inserts/voices gradually while watching memory/CPU through Xcode. No capacity benchmark is implied by the configured track limit.
- Record while importing/exporting controls are disabled. Verify a simulated storage failure reports an error and never overwrites an existing take.

## 0.1.1 regression checks

- Mouse/trackpad: click-hold-drag both directions across audio clips on two tracks. Selection highlights while dragging; release opens edit menu. Touch/Pencil: hold then drag. A short swipe still scrolls.
- Add mode extends a selection with a second sweep; tap toggles a clip. MIDI lanes stay excluded. Cancel a gesture and check that the prior selection returns.
- Duplicate a group with gaps, Cut/Paste at cursor on original tracks, Split only intersecting selected clips, add/remove fades and delete. Undo each action once, then Redo. Check original assets are intact and save/reopen to confirm edits persist.
- Move mode: drag a selected group with Snap on/off; preserve gaps and clamp at beat zero.
- Confirm top ordering: Grid → Undo → Redo → Loop; Record → Count-in → Counter. Narrow layouts scroll and do not permanently hide controls.
- Cycle Count-in Off/1 Bar/2 Bars and verify persistence after relaunch. With Click OFF, hear exactly the count-in, then silence from the metronome during the take. With Click ON, verify ongoing ticks continue. Test audio and MIDI takes at beat zero and a later cursor.

## 0.1.2 additions

- Select a clip. Drag cyan left/right side edges inward, then outward to restore source audio. Confirm timeline snap, source offset, unchanged opposite edge and undo/redo. Drag orange upper corners for fades; Shift-click the fade to cycle curves, and repeat using the touch menu. Listen for each fade.
- Open Sampler / XY on an instrument track. Import a small WAV into Keyboard, crop/fade, Apply, play keys, record and reopen. Repeat for all eight pad slots. Unassigned pads should retain starter sounds. Test One-shot and Loop, including Stop. Check memory and audio stability on the legacy iPad.
- Test MIDI XY pitch/velocity, Pitch matrix off for repeat-rate mode, Note repeater on/off, independent Snap, root selection, note recording, finger release, track switching and closing the panel without stuck notes.
- Enable Audio XY on a track. Test all six modes and both Snap states during playback; change modes and reopen the session. Listen to tempo changes, dry/wet, pitch fine control, gate/wah/flange timing and repeater capture. Export WAV and compare timing/output. FX gestures are not recorded as automation.
- Build/run Legacy, Pro and Catalyst; test Shift-click via a hardware keyboard/pointer and touch-only curve controls. Confirm selected-edge gestures do not initiate marquee/move/scroll unexpectedly.

## 0.1.3 additions

- Build all three schemes; run DBALNativeMac on Apple Silicon and PocketLegacy on iPadOS 15.4.1. Run both Swift test scripts on the Mac.
- Stretch a pitched sample to 200%, retaining pitch; shift +12 semitones, retaining prepared duration; combine both. Apply and audition. Rebuild/reopen to verify cache reuse. Restore defaults and verify original audio stays intact.
- Preview 1–8 equal slices and transient slices in a cropped source; check visible boundaries, unchanged source, per-pad fades and one-step populate undo.
- Populate A then F; check that B–E remain empty, all assignments survive reopen/export/import, recorded F notes still play when A is visible, bank A old-project note mapping stays intact, and empty slots stay silent after chopping.
- Reject excessive sample memory without a crash or partial successful instrument claim. Test stretch/pitch before live monitoring on the old iPad.
- Native Mac: AU v2 and AUv3 discovery, MIDI, editor/generic fallback, per-instance state, missing-plugin behavior and offline mix. Test audio recording, stop/loop/count-in and safe project transfer both ways. Mac UI currently omits marquee selection.

- Remote mode on both iPads: advertise/connect Bluetooth, refresh/select destination, play/release all keys/pads, change channel/destination with held notes and verify no stuck notes. Check Network MIDI separately and verify closing Remote restores local engine playback. Confirm local recordings are not started/altered in Remote mode.
- Native Mac input: connect first, then enable/refresh input; arm/select an instrument and record notes. Confirm CC7 on channels 1–8 affects the corresponding track, CC16 only crossfades tracks 1/2 when enabled, Start/Stop works, Panic releases notes, input off and reconnect do not duplicate events. Check an independent MIDI monitor for exact channel/CC bytes. MIDI clock/automation/feedback are not implemented.
