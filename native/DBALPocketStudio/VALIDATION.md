# Validation performed for 0.1.4

Environment: Linux; no Swift compiler, Apple SDK, Xcode, iOS simulator, physical iPad or Mac runtime available.

Passed:
- Generated Xcode OpenStep project parses structurally, all project/source/resource references resolve, all 23 Pocket Swift/C source files belong to each target, and both shared schemes reference real targets.
- Deterministic regeneration produces the same project. Legacy/Pro flags, iPadOS 15.4 deployment baseline, Catalyst support, microphone/background-audio/document metadata and eight bundled WAV samples were checked.
- The C11 sampler builds with `-Wall -Wextra -Werror -pedantic` and runs under AddressSanitizer + UndefinedBehaviorSanitizer.
- Runtime C assertions cover silence, note-on/release, note/velocity ranges, panning, sustained loops, one-shot/panic, invalid regions, bounded event queue overflow/recovery, concurrent MIDI producer/render consumer, bounded recording backpressure, and advancing/manual host transport context.

LeakSanitizer was unavailable because process metadata is restricted in this environment; it is disabled in the portable test command. Address and undefined-behavior checks remain enabled.

Not performed: Swift syntax/type checking, Xcode project opening/building/signing, Catalyst compatibility, audio-device performance, AUv3 discovery/instantiation/UI/state/musical context, SF2/SFZ end-to-end app playback, actual recording alignment, UI visual QA, background playback, portable-session transfer or real WAV export. Structural checks and C tests do not establish these behaviors. The project requires the device checklist before it can be called a working/validated DAW.

New clip-edit Swift tests are included but NOT RUN here (no Swift compiler). Their cases cover forward/reverse and cross-track selection, ignoring MIDI lanes, duplicate/cut/paste geometry, source offsets, split edges, move/fade clamping and value-snapshot isolation. Hardware gesture/scroll interaction, popup placement, multi-edit undo and the new count-in behavior are not verified. The original version compiled with user-applied fixes and recording was reported working; those fixes are included in this release.

0.1.2: All six audio XY modes were exercised under ASan/UBSan with stereo bounds, long ring-buffer wrap, dry mix and gate attenuation checks. These portable tests passed. Swift regression cases now also cover trim/restore, file boundaries, fade curves, tempo divisions and session serialization, but remain NOT RUN. Custom AU resource allocation, native pitch processing, sample loading and every new gesture still require an Apple build and device test.

0.1.3: Deterministic project parsing now checks a third, separate native macOS target, its shared-engine membership and UIKit-only exclusions. Added Swift regression cases for six-bank serialization, 48 distinct note mappings, equal/transient chop bounds and inherited transforms. Added a macOS-only offline transform test for output duration/frequency and cache preservation. Both Swift test suites remain NOT RUN here. Native Mac UI, AU v2 MIDI/state/editor behavior, sample stretching and all new bank/chop controls require Apple build/device validation. No GPU/ML acceleration or performance benchmark was performed or claimed.

Remote mode: added MIDI byte-decoder regression cases (running status across packets, interleaved real-time messages, CC and ignored SysEx). These Swift cases are NOT RUN here. Bluetooth/RTP-MIDI permission, discovery, endpoint routing, native receive/recording and fader/transport control are all hardware-unverified.

0.1.4: Shared graph connects now cross an Objective-C exception boundary and reject zero-input non-mixer destinations. Structural checks include the .m source in all three targets. Existing C sampler/FX sanitizer tests pass. The new macOS Objective-C guard regression and Apple build are NOT RUN here. User-provided stack confirms the failing AVFAudio assertion but does not identify the exact destination node. No claim of reproduced/resolved hardware behavior is made.
