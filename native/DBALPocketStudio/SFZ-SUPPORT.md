# SFZ support in 0.1.0

Supported headers: `<control>`, `<global>`, `<group>`, `<region>`. Global and group inheritance applies to regions. Supported opcodes:

| Opcode | Behavior |
|---|---|
| sample | File under the imported SFZ directory; decoded with AVAudioFile |
| default_path | Prefix in the control header; relative paths only |
| key / lokey / hikey | MIDI key range; integers or scientific note names, C4 = 60 |
| pitch_keycenter | Root MIDI key |
| lovel / hivel | Velocity range |
| volume / pan | Region dB gain / pan (-100 to 100) |
| tune / transpose | Cents / semitones, combined at playback |
| loop_mode | no_loop, one_shot, loop_sustain, loop_continuous |
| loop_start / loop_end | Explicit sample-frame positions; SFZ inclusive loop_end is converted internally |
| ampeg_release | Exponential release duration parameter, constrained to 0.005–30 seconds |

Loop bounds must be explicit; WAV embedded loop metadata is not interpreted. one_shot plays through note-off; Stop/Panic still releases voices. loop_sustain exits the loop on note-off; loop_continuous continues looping during release. Pitch uses linear resampling: large transpositions can alias. Every region is mono internally; stereo samples are averaged. A short fixed attack suppresses discontinuities. The built-in keys tone is synthesized rather than sampled.

Includes, macros and generator samples are rejected. Unrecognized opcodes are listed in the status warning and ignored. In particular, **seq_length/seq_position, group/off_by, trigger, offset, end, envelopes beyond release, filters and modulation are not implemented**. A library using these can sound different even if it loads. There are at most 256 regions per instrument. Imported sample paths cannot leave the selected folder; symbolic links are rejected during import. SFZ folder imports require exactly one definition at the top level.

Use compact straightforward instruments for the first tests. Full SFZ compatibility and a streaming engine would be a separate development milestone.
