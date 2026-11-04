# VII Voice-to-Instrument — Mac AUv3 integration foundation

This is a **real DSP prototype**, not a compiled AUv3 or a finished host-integrated plugin. It provides allocation-free, per-block C processing: mono vocal/whistle pitch tracking (80–900 Hz), gate, smooth pitch tracking, voiced envelope and an original additive reed-like tone. Run `sh native/VII/Scripts/test-core.sh`. Output defaults to /tmp; set VII_BUILD_DIR to an SD-card path.

## AUv3 design for DBAL
1. Create a macOS Audio Unit Extension app with **Music Effect** type (`aumf`), subtype `VoII`, manufacturer `DbAL`. Use its audio input bus for microphone/DAW audio and output bus for synthesis. Never directly open the microphone inside the extension.
2. Wrap `VIIEngine` in a render-safe AUAudioUnit; preallocate state before rendering, use stereo-safe channel handling, support sample-rate changes and wet/dry automation. Host mic/voice track -> VII music-effect insert -> DBAL mixer.
3. Later add an **Instrument** AUv3 (`aumu`, distinct subtype `ViIN`) for MIDI-driven playback and standalone voice-to-MIDI forwarding, using a shared engine.
4. For Mac DBAL, the plugin browser already supports Music Effects in the effect category. **Host-side microphone monitoring/routing and live MIDI recording still need actual validation.**
5. Integrate DNA/VTI preset loading, articulation estimation, pitch bends, transient-based note boundaries, latency measurement and fullState save/restore before declaring parity.
6. Add an AUv3 project and sign/install containing app; validate with `auval -a` and live DBAL microphone-to-track tests. No build or Mac audio runtime verification is claimed here.

### Known limits
Autocorrelation is monophonic, can mis-detect octaves, does not distinguish breath from pitched notes robustly, and has a warm-up/tracking delay. Add confidence gating, hysteresis, octave correction, noise handling and tests using real vocals. DSP core is deliberately not an ML model.
