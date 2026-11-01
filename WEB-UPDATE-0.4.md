# Browser 0.4: parity foundation

Implemented: decoded multitrack audio scheduling, MIDI clip/note playback and numeric editing, note capture from keyboard/pads, input and editor quantize, undo/redo, track mute/solo and volume, microphone clip decoding, multi-file import, draggable dock height and adjustable key width.

Native parity remains incomplete. SF2/SFZ, Instrument DNA, effects, waveform rendering/processing, session persistence, count-in, remote MIDI and a playable step sequencer still require work. Unsupported legacy panels now state their limitations. The drum pads currently audition pitched synth tones; no drum sampler is claimed.

Verification: JavaScript syntax checks and diff whitespace checks. Browser audio, touch gestures, microphone permissions and iPad Safari runtime have not been verified. Mixer changes apply on next transport start; import buffers are session-local.

## Continued audio editing pass

Added first-channel waveform display for the selected audio clip, source-offset trimming without modifying the imported buffer, clip splitting at the playhead, and fade-in/out controls connected to scheduled Web Audio gain ramps. Fade controls use seconds; timeline start/length use beats. Automated assertions cover fade boundaries and scheduling when playback begins inside a fade. Browser rendering and audible playback remain unverified.

## Sample instrument pass

Added per-track audio sample loading, editable MIDI root note, root audition and pitched sample voices used by both the performance keyboard and scheduled MIDI clips. Undo/redo includes instrument assignments. Sample data is session-local, with no SF2/SFZ or DNA model parser. Pitch mapping uses playback-rate transposition, changing duration. Automated tests verify octave-up and octave-down playback rates; browser audio remains unverified.

## Persistent current session

Added IndexedDB autosave of the current arrangement, MIDI notes, clip edits, instrument sample assignments, decoded PCM audio, tempo and position. Reload restores audio data independently of temporary blob URLs. A visible status reports save/restore success or storage failures; Save session also requests a save. Restore temporarily locks editing to avoid overwriting new edits. Debounced saves run after edits; wait for the saved status before closing. Browser storage is device/browser-specific and may be cleared by private browsing, browser settings or eviction; it is not a portable backup. PCM snapshot tests cover deduplication, copied samples and missing-audio rejection. Actual browser reload persistence and quota behavior remain unverified.

## Instrument DNA input

Added Playable Comparison JSON import using the current Instrument DNA repository's own validators. Base note slices are mapped by nearest MIDI anchor, playable through keyboard and MIDI clips, and included in persistent session audio. Audio-free Reflections are explicitly rejected; physical synthesis, HybridStretch, and articulation-layer playback remain pending. Engine modules copied from diallo100x/instrument-dna-web; see DNA-ENGINE-SOURCE.md. Syntax, module dependency loading and malformed-format rejection checks pass; browser end-to-end import/audio remains unverified.

## Extended DNA behaviors

Physical-model Reflections now import through DNA validation and its physical-fit selection/rendering code. Import renders nine two-second anchors at MIDI 48–72 / 22.05 kHz, with playback-rate mapping elsewhere. This is a rendered bank, not continuous native physical synthesis. Physical control wiring is partial; exact native timbre equivalence is not claimed. Nonphysical audio-free Reflections still require a Playable Comparison.

Comparison articulation-layer samples now persist with the session and can be selected via sustain/trill/staccato/accent/breathy/alternate controls. Optional velocity switching uses the saved trill threshold, with base-anchor fallback where a layer is absent. Continuous mono/legato, HybridStretch, full parameter parity and per-note articulation editing remain pending.

Verification: syntax, whitespace, and a physical-render smoke test verifying nonzero finite PCM. Full browser import, persistence reload and audible comparisons remain unverified.

## Legato and HybridStretch pass

Connected the original DNA granular renderer with a bounded 48-entry cache. Supported stretch range is ratio 0.75–1.34 and notes up to four seconds; out-of-range notes use rate playback. Per-track poly/mono/legato modes and 10–2000 ms glide settings are saved in session state. Legato reuses an overlapping sample voice, loops its middle segment and glides playback rate without restarting its attack. Keyboard mono/legato release and prior-held-note return are connected; live notes currently cap at four seconds. Gliding a stretched voice changes its rate and does not preserve independent timing during the transition. MIDI notes within each clip are sorted for scheduling; cross-clip overlapping voice ordering still requires further work. This is sample-based legato, not native continuous physical synthesis.

Verification: syntax/whitespace and granular renderer duration, finite/non-silent output and unsupported range checks pass. Audible transitions, sustained-note behavior, iPad touch, and full browser regression remain unverified.

## Browser QA — November 1, 2026

Desktop Chrome preview opened successfully. A generated physical Reflection imported nine anchors and reported successful IndexedDB save. After page reload, the Instrument DNA panel showed the same nine anchors with HybridStretch checked and legato mode retained. Keyboard C4/D4 capture produced editable MIDI notes; overlapping notes were scheduled through transport and the position advanced through the four-beat arrangement. Stop responded. Inspected console errors were browser-extension metadata errors, not DAW errors.

These checks establish UI/runtime operation and state restoration, not audible quality, waveform equivalence, real overlapping finger gestures, or physical iPad Safari behavior. Initial test upload failed because the fixture was outside the browser shared directory; using the documented shared path resolved it. No publication performed.
