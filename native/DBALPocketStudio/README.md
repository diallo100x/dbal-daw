# DBAL Pocket Studio 0.1.7 — resizable performance dock

A separate native DAW project for Diallo Beats, prioritizing an iPad limited to iPadOS 15.4.1. No changes to DBAL Web DAW or the DJ DAW. No account, API, network service, package manager, or AudioKit dependency is required.

**This is an initial source prototype, not a verified device build.** The portable C sampler and project structure were tested in Linux. Native Mac and Legacy simulator compilation, edit logic and offline audio checks run in CI. Signing, hardware audio routing, AUv3 sessions, Bluetooth/network MIDI, background recording and gesture layout still require device validation. There is no precompiled IPA in this ZIP.

See **UPDATE-0.1.7.md** for the resizable pads/keyboard, lock and repeater matrix. See **UPDATE-0.1.6.md** for Audio Unit discovery refresh and diagnostics. See **UPDATE-0.1.5.md** for Mac track/lane selection, piano-roll and waveform editors, input monitoring, Bluetooth and network MIDI settings. See **UPDATE-0.1.4.md** for the reported Mac connection-crash protection and rebuild instructions. See **UPDATE-0.1.3.md** for the native macOS target, AU v2/AUv3 hosting, sampler time stretching/pitch, six banks of eight slices, Pocket MIDI Remote mode and build/test commands. Prior Pocket features remain included.

## Native Mac build

Open DBALPocketStudio.xcodeproj, choose **DBALNativeMac → My Mac**, select your signing team, and press Command-R. This uses the shared engine in an AppKit/SwiftUI shell rather than Catalyst. It is a foundation with current recording/editing/sampler features, not the finished full DAW. Read UPDATE-0.1.3.md for exact scope and limitations.

## Open and run

1. Extract the ZIP on your Mac. Open **DBALPocketStudio.xcodeproj**.
2. Select the **PocketLegacy** scheme and your older physical iPad. Deployment target is **15.4** (includes 15.4.1).
3. Under the PocketLegacy target → Signing & Capabilities, choose your development team. Change the bundle identifier if your account requires it. Automatic signing is enabled; no AUv3 extension target or extra extension App ID is needed because this app is a host.
4. Press Run. Accept microphone permission when recording your first vocal take.
5. Use **PocketPro** for the newer iPad. To build the closely matched Mac version, select **My Mac (Mac Catalyst)** under either scheme. The Mac deployment baseline is macOS 12.3; the separate DBALNativeMac target now provides the native desktop shell and AU v2 discovery path. The separate DBALNativeMac target is Apple-built in CI; Catalyst is not covered by that build.

Command-line alternatives, with full Xcode installed/selected:

```bash
./Scripts/build.sh Legacy ios YOUR_TEAM_ID
./Scripts/build.sh Pro ios YOUR_TEAM_ID
./Scripts/build.sh Pro mac YOUR_TEAM_ID
./Scripts/build.sh Legacy simulator
```

The project is already generated. Python is needed only for optional regeneration/tests, not to open or build the app. No Homebrew/XcodeGen/CocoaPods setup is required.

## First session: a beat and vocals

1. Select **Beat / Audio**, then **Import Audio** and choose a local audio file.
2. Select **Vocals**, tap **R** to arm it, and place the cursor by tapping the timeline ruler. R is exclusive: one audio or instrument track can be armed at a time.
3. In Settings, select input/buffer and optionally enable headphone monitoring, then **Apply Settings / Restart Audio**. Input selection is device-level; individual interface-channel selection is not implemented. All channels supplied by the current input format are captured.
4. Tap **Record**. Tap **Stop** to finish. Recording creates a new nondestructive clip. Metering is active during audio recording.
5. Select the clip and open **Clip Editor** for source offset, length, fades, split, duplicate, or delete. Drag a clip to move it; snapping uses the selected grid. Move the cursor with the ruler before splitting.
6. Use Session → **Save + Plugin Settings**, **Export Portable Project**, or **Export Stereo WAV**.

Stop pauses at the current cursor; pressing Stop again returns to zero. Loop start/end are editable in Settings and shown by the orange strip above the timeline. Record bypasses loop cycling to retain one continuous take. Count-in ticks play whenever Pre-roll is enabled; Click controls the ongoing metronome.

Audio remains at its original speed. Tempo changes move beat-based clip positions and preserve the clip's audio duration; this is not time stretching. Timeline zoom and scrolling support long sessions. Clip edits produce chunked cache files, excluded from portable exports. Original sources remain in Assets, including files no longer referenced after edits/undo, so project exports can retain unused takes.

## Instruments and inserts

- Add/select an **Instrument / MIDI** track. Use the instrument menu below the timeline.
- **Starter Keys:** lightweight synthesized keyboard tone.
- **Starter Drum Kit:** eight original synthesized GM-mapped percussion samples, bundled offline. Use Pads. This compact CC0 starter set is **not** the requested large third-party/open-source sound library; no such library is bundled or claimed.
- **Sampler Keys / Sampler Pads:** open **Sampler / XY** to import samples, edit crop/fades and assign eight pads. Each track uses either a keyboard sample or its pad kit; see UPDATE-0.1.2.md.
- **SF2:** import a local `.sf2`; change zero-based program and bank MSB/LSB in Settings. Apple's sampler renders SF2. Large soundbanks may exceed old-iPad memory even when the file itself fits on disk.
- **SFZ:** choose **Import SFZ Folder**, selecting a folder with exactly one top-level `.sfz` and all its samples below that folder. The whole folder is copied into the project. Flatten definitions that use includes/macros first. See SFZ-SUPPORT.md.
- **AUv3:** choose an installed compatible instrument. Use **Instrument UI** for its editor. **+ AU Effect** adds track inserts; their menus open/remove them. The host supplies tempo, meter, beat, loop and transport context. Cross-host compatibility and individual DBAL plugins need device testing.
- Arm an instrument track, tap Record, and play the onscreen piano or pads to capture MIDI notes. MIDI Editor adds/deletes notes and adjusts pitch and grid position. This is a basic note editor, not a full piano roll/automation suite.

Legacy permits adding up to 8 tracks and uses 16 sampler voices per internal instrument; Pro permits adding up to 32 tracks and uses 48 voices. These are configured limits, **not measured hardware capacity**. Shared projects with more tracks can open in Legacy (up to the schema safety limit of 64); they may exceed the older iPad's processing/memory capacity. SFZ decode budgets are conservative and per instrument: 64 MiB Legacy / 256 MiB Pro. Multiple instruments and third-party plugins add to total memory use. Default requested IO buffer is 512 frames Legacy / 256 Pro; hardware can negotiate a different size.

## Portable projects

Each `.pocketstudio` package contains Session.json and Assets. Imported recordings, SF2 files and complete SFZ folders are copied into Assets. Paths are relative, path traversal/symbolic links are rejected, and JSON saves are atomic. Sessions live in the app's Documents/Sessions folder and the latest session reopens on launch. Files/iTunes file sharing is enabled. Exported project packages can be opened via the project picker or the app's file-type association.

Plugin identity uses component type/subtype/manufacturer and state is saved as a binary plist per instance. A missing plugin's reference/state remains in the project; a status message reports the missing instance. Its processing is unavailable; an unavailable effect is omitted in live playback. Stereo export refuses a session with a required missing instrument/effect. AU state can still contain a plugin's own external file references; copying the host project cannot make those external samples portable. Use each plugin's own asset export/import facilities when needed.

The Mac needs its own compatible installed Mac plugin, with a matching component identity and state format. An iPad AUv3 binary is not transferred to or executable on the Mac by this project. Mac Catalyst plugin discovery/editor compatibility is unverified. Identical project schema does not guarantee identical third-party plugin output across platforms.

## Current limits

- Swift/Xcode/device execution is unverified. Treat this as the first compile-and-test handoff.
- Live/sequenced MIDI uses a 5 ms main-run-loop scheduler; UI playhead redraw is capped near 30 Hz. MIDI timing is not sample accurate and can jitter under load. Audio files use scheduled engine times. Offline MIDI is dispatched at render-block boundaries split at note events, but plugin render behavior still needs testing.
- Recording uses a bounded queue of 16 copied PCM buffers. If storage falls behind, finishing reports a failed take rather than silently claiming an intact recording. A failed/incomplete take may remain in Assets for recovery. Input routing/round-trip latency and monitoring are not calibrated. Inserts process playback, not the recorded input file.
- SFZ is a subset; stereo regions are downmixed to mono and samples are loaded into RAM. No disk streaming, round robin, choke groups, scripting, or advanced modulation.
- Full third-party sample library, per-track freeze/unfreeze, sample-accurate MIDI scheduling, CoreMIDI hardware input, parameter automation, time stretching, comping/take lanes, and a full piano roll are not implemented.
- WAV export is offline, 24-bit stereo, at the current engine output rate, with a fixed two-second tail. Long reverb tails may be cut. Plugins that cannot render offline can fail export. Export stops/releases the live graph first to reduce duplicate memory use, then rebuilds it.
- Background audio is declared, but uninterrupted lock-screen recording/playback has not been demonstrated on hardware. Route changes/interruption stop transport and call for an audio restart.

See DEVICE-TESTS.md and VALIDATION.md before relying on this for an important recording.

## Source layout

App/AudioEngine.swift owns the AVAudioEngine graph, recording, AU loading/state/context and WAV rendering. App/Studio.swift owns transport and document operations. App/Session.swift defines portable data and validation. App/SFZ.swift implements the subset loader. App/StudioView.swift and Panels.swift provide the common touch interface and Catalyst UI. Engine/PocketSampler.c supplies the bounded sampler voice engine, atomic MIDI queue, record backpressure counter and atomic host-context data.

Run `./Scripts/test.sh` on a machine with Python 3 and a C11 compiler to repeat the portable tests. The script uses address/undefined-behavior sanitizers; leak scanning is disabled because the creation environment cannot expose the required process metadata. Run the Xcode build separately for Apple compilation.
