# 0.1.7 (build 8): performance dock

The main iPad and native Mac views now include a shared performance dock with
Undo/Redo beside the pads/keyboard selector. Both retain session edit history;
performance gestures and layout preferences themselves are not session undo items.
The existing editor and transport undo controls remain available.

Drag the dock's top edge up/down to change its height (220–460 points). Pad rows
and piano key heights follow the available dock space. Height persists on the
device. The top-right XY repeater controls remain beside the playable area.

XY defaults to X = tempo-relative repeat timing (four beats through 1/64 note),
Y = velocity. Choose Y: Pitch for ±12 semitones while X still controls timing.
Snap gives musical divisions and semitone steps; free timing varies continuously.
The optional Pitch / Velocity mapping remains in the full MIDI controls panel.
The compact dock changes held keys/pads; touching XY alone does not generate an
extra root note. Enable Note repeater, then hold a key/pad. Changes apply to the
next repeat, and recorded repeat events retain their generated pitch/velocity.
MIDI timing still uses the existing 5 ms scheduler, not sample-accurate scheduling.

Locked is playing mode. Unlock switches the piano surface to layout editing:
drag horizontally to move the visible MIDI range, pinch to resize key widths,
or drag Resize keys. Octave buttons and Fit 2 octaves also operate while unlocked.
All 128 MIDI pitches are available by panning; keys are 22–110 points wide.
This adjusts the uniform keyboard layout/range, not individual key pitch mappings
or freely rearrangeable keys. Key width/range/lock persist as device preferences.

Changing lock, matrix axes, repeater enabled state, view, track, or panel layout
releases performance notes. Each touch also releases on disappearance. Layout
editing does not trigger notes. Incoming Mac MIDI velocity now scales with the
matrix velocity rather than always being replaced by a fixed 100; ordinary
recorded notes retain their actual generated velocity.

No session schema or source audio changes. Third-party iPad AU discovery still
requires the physical-device acceptance described in UPDATE-0.1.6.md. Touch
resizing/chords, host editor behavior and exact visible layout need hardware QA.
