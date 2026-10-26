# DBAL native foundation and Pocket sampler update

## Open in Xcode

```bash
cd ~/Downloads/DBAL-Pocket-Studio-0.1.3
open DBALPocketStudio.xcodeproj
```

- **DBALNativeMac → My Mac:** separate native macOS app, macOS 12.3 minimum. Choose your signing team and press Command-R.
- **PocketLegacy → your old iPad:** iPadOS 15.4 minimum, compatible deployment baseline for 15.4.1. Same bundle identifier as the prior Pocket Legacy build.
- **PocketPro → your newer iPad:** shared engine with higher limits. Existing Catalyst builds also remain available.

For a Release build from Terminal, run `bash Scripts/build_native_mac.sh YOUR_TEAM_ID`. Pocket installs directly from Xcode on a Mac that recognizes the iPad; Sideloadly is optional. Export sessions before updating and retain the installed Pocket app.

## Sampler: independent stretch and pitch

Open Sampler / XY on an instrument track and import a sample into Keyboard or a pad slot. The waveform editor retains crop/fade handles.

- Stretch adjusts duration from 25% through 400% while retaining pitch.
- Pitch shifts the prepared sample from −24 through +24 semitones while retaining duration.
- Fit to BPM calculates a duration multiplier for the chosen number of beats at the current session tempo; the 25–400% limit still applies. This is a one-time edit, not continuous tempo-following or automatic source-BPM detection.
- Apply Crop / Fades prepares the result using Apple's offline time/pitch unit. The source file stays intact. Crop and fades use source-time units; stretching scales those envelopes along with the sample.
- Sample transformations use a regenerable project-local cache. It is excluded from portable exports. Reopening/exporting can regenerate missing results.

Keyboard playback transposition remains traditional sampler varispeed: playing different keys changes speed and duration. The saved stretch/pitch controls are independent preparation settings, not per-note tempo-lock. Apply briefly stops playback while the graph rebuilds.

## Six slice banks, A–F

Each bank has eight rectangular pads. Use the **<** and **>** arrows in the sampler editor or above the pads to change banks. Bank changes stop transport/held notes safely, retain assignments and require no sample reload.

1. Import or select a source sample, then crop to the section you want.
2. Choose 1–8 slices. Leave Transients off for equal slices; enable it for simple peak-envelope onset detection.
3. Tap Preview Chop. Yellow markers and source-time ranges show proposed boundaries. Transient mode can return fewer slices when there are fewer detected attacks; equal mode produces the requested count.
4. Select the destination bank A–F and preview again if changing banks cleared the preview.
5. Populate Bank replaces that bank's eight slots in one undo step. Other banks remain intact. Empty slots stay silent after chopping, including in bank A.

Slices reference the original source, inherit its stretch/pitch settings and receive short edge fades. No duplicate audio files are created. Preview uses a 1024-bin waveform envelope, so very fine transients can be missed; edit individual slice crop boundaries afterward when needed.

Bank A keeps the previous GM pad notes: 36, 38, 42, 46, 41, 45, 49, 51. B–F use notes 60–99. Recorded MIDI therefore identifies the actual slice independent of the visible bank. Existing projects without bank metadata open as bank A. All assigned banks are loaded within the existing per-instrument memory budget; this is not disk streaming. Legacy can reject large banks rather than over-allocate.

## Native Mac edition

The new target uses AppKit/SwiftUI rather than Catalyst, with the shared session model, audio engine, recording, sampler and offline export. It includes a desktop timeline, track gain/mute/solo/arm, audio and instrument tracks, audio/SF2/SFZ import, MIDI playback/recording, metronome/count-in, clip trim/fades, undo/redo, sampler/XY panel and portable project open/export.

The native component picker includes AU v2 and AUv3 instruments and effects. AU v2 MIDI has a legacy MIDI-event fallback. Plugin state uses the shared component identity/state format. Custom editors are requested through the Audio Unit wrapper; a generic parameter editor is available when a custom controller is absent. Install compatible Mac plugins; iPad binaries do not transfer. VST/VST3/CLAP hosting is not included.

This is the first native Mac foundation, not a completed full DAW. The Mac timeline currently supports individual clip selection and right-click editing, not the iPad marquee overlay. Bus/send routing, full automation lanes, advanced piano roll, stem separation, freeze and neural analysis are not implemented. The Mac currently uses the system audio devices; dedicated device/channel selection is not included.

The desktop build is not App Sandbox restricted to allow traditional third-party AU hosting, and its hardened-runtime entitlements allow loading third-party plugin libraries. No installer, notarization or signed release is supplied.

## Pocket Remote mode

Pocket Legacy and Pocket Pro now have a **Remote** button. This opens a MIDI controller screen and pauses/releases the local audio engine to reduce CPU use. Returning to Studio rebuilds local playback.

- Two-octave piano with octave and channel controls, eight GM drum pads, eight vertical channel faders, a crossfader, Start/Stop and Panic.
- Faders send CC 7 on channels 1–8; the crossfader sends CC 16 on the selected keyboard channel. Start/Stop sends MIDI real-time Start/Stop. MIDI clock and audio streaming are not included.
- Bluetooth MIDI opens Apple's peripheral-advertising panel on physical iPads. On the Mac, open Audio MIDI Setup → MIDI Studio → Bluetooth, then connect the iPad. Refresh the Pocket destination list and select the connected destination. Connection/advertising may need re-establishing after sleep.
- Network MIDI enables the app's RTP-MIDI session while the panel is open. Connect it from the Mac's MIDI Network Setup on the same local network, then use its destination. Network/Bluetooth permission prompts are system-controlled. The panel restores the network enable/policy settings it changed on exit.
- Virtual output is for other MIDI apps on the same device. Selecting it alone does not connect to another device.
- Destination/channel changes release held notes. Panic additionally sends All Sound Off/All Notes Off to all channels. Connection success does not prove the receiving host is mapped correctly.

In **DBALNativeMac**, select the instrument track and click **Enable MIDI Input** after connecting the iPad. Notes play/record through that selected track; they currently use the host's on-screen velocity behavior rather than preserving arbitrary incoming velocity. CC 7 channels 1–8 control the first eight track gains. Incoming Start/Stop controls transport. Refresh MIDI input after connecting new devices. Generic third-party DAWs require their own MIDI input/MIDI-learn setup.

The native Mac's **CC16 → tracks 1/2** checkbox optionally maps the crossfader to equal-power gain changes on the first two tracks; those changes replace their current gain values. It is off by default. Remote changes do not create automation lanes or send motorized-fader/position feedback.

Both Pocket editions retain a 15.4 deployment baseline in this release. Pro has higher memory/voice/track limits; new-iPadOS-only interfaces can be added behind availability checks without breaking Legacy. There is no claim that Pro already uses every feature of the latest OS.

Bluetooth/network operation, end-to-end latency and background reconnection have NOT been verified on hardware. Keep the remote screen active for initial testing.

## Lightweight processing policy

Audio playback uses the CPU/native audio framework. Stretch and pitch preparation runs in a background task, with bounded memory and cached results, instead of adding a stretch processor to every live voice. Both editions avoid bundling neural models or launching unused analysis workers. The Mac uses the Pro profile (32-track creation limit, 48 internal voices and 256 MiB sample preparation budget per instrument); these limits are not measured hardware capacity. There is no custom Metal/Core ML/Neural Engine workload yet: those backends should accompany a specific future analysis feature with measurements, not run merely because the machine has them.

## Checks and remaining validation

Portable C sampler/FX sanitizer tests and structural checks for all three Xcode targets pass. Swift regression tests cover bank mapping, old-session defaults, serialization and chop ranges. A Mac-only offline audio test measures stretch duration, independent pitch, cache reuse and source preservation.

**Neither Swift tests nor Apple builds ran in the creation environment:** no Swift compiler, Apple SDK or Xcode is available here. Run on your Mac:

```bash
bash Scripts/test_clip_edits.sh
bash Scripts/test_apple_audio.sh
```

Then build/run the desired scheme. Verify microphone capture, pad bank recording, audible transforms, plugin scanning/editor/state, saved project exchange, WAV export and legacy-iPad memory/gesture behavior. The previous successful Pocket recording does not validate these new paths.
