# Mac audio-graph crash protection

The supplied crash log reports an uncaught AVFAudio exception during `AVAudioEngine.connect`: the destination has no inputs and cannot grow them. The release stack does not identify the particular node/plugin. This patch addresses that failure path without deleting sessions or assuming a specific plugin caused it.

- Every shared-engine connection now uses an Objective-C guard. Zero-input destinations are rejected before connection, except growable mixer nodes. AVFAudio connection exceptions become normal host errors rather than escaping Swift's error handler and terminating the app.
- Inserts must expose audio input and output buses. A rejected third-party insert is reported and bypassed in live playback; its saved reference/state is retained. It is counted as loaded only after successful connection. Offline export still refuses sessions with required unavailable processing.
- Engine prepare/start has the same exception boundary. An invalid built-in XY chain reports an error and stops that rebuild rather than pretending it rendered successfully.
- Each attempted connection logs source/destination descriptions and bus counts, making a remaining failure identifiable. The graph teardown avoids creating/accessing the microphone input merely to compare node identities.

## Build the Mac update

```bash
cd ~/Downloads/DBAL-Pocket-Studio-0.1.4
bash Scripts/build_native_mac.sh
open Build/Build/Products/Release/DBALNativeMac.app
```

The native Mac bundle ID is unchanged. The old Dock shortcut points to the old build folder: launch the new build and replace its Dock shortcut if needed. Sessions and plugin state are retained. No preference reset or project deletion is required.

If a routing error appears, copy the displayed track/effect error. If needed run the new binary directly to capture detailed connections:

```bash
./Build/Build/Products/Release/DBALNativeMac.app/Contents/MacOS/DBALNativeMac 2>&1 | tee ~/Desktop/DBAL-Mac-launch.log
```

This protects the reported crash path; it is not proof that every plugin or the new Mac graph works. The exact offending node still needs confirmation from this build's diagnostics. The Objective-C guard and native app could not be compiled/run here because Apple SDKs/Xcode are unavailable.

On the Mac, `bash Scripts/test_graph_guard.sh` exercises rejection of a zero-input destination and acceptance of a mixer. Existing portable C sampler/FX tests and deterministic project checks pass. All prior sampler banks, stretching and remote-mode features remain included.
