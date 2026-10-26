# DBAL DAW
Touch-first browser DAW prototype by Diallo Beats Audio Lab.

## Live testing
Designed for GitHub Pages and Safari/iPad testing.

Current scaffold: 8 audio/MIDI tracks, arranger, audio import/playback, transport, mixer, pads, keyboard, editor and plugin-rack views.

## Native Mac and iPad source

The preserved native Pocket Studio project and current Mac editing update are in
`native/DBALPocketStudio`. Open its `DBALPocketStudio.xcodeproj` and choose
`DBALNativeMac` for the desktop app or `PocketLegacy` for iPadOS 15.4.1. See the
native README and UPDATE-0.1.5.md for track selection, waveform/piano-roll editing,
input monitoring and Bluetooth/network MIDI settings. Native Apple builds and
offline regression checks run in `.github/workflows/native.yml`.
