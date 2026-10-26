# 0.1.5 · Mac track selection, timeline editors, monitoring and MIDI setup

Mac track headers/rows and empty timeline lanes select and highlight the active
track. The inspector and MIDI input follow that selection. Switching tracks
releases held/repeating performance notes and closes the previous instrument UI;
record arming remains independent. Audio clip clicks select and open a larger
waveform editor. MIDI lane/note clicks open a piano roll for that track.

Audio edges trim the source offset/length without changing the recording. Upper
or lower corners set fade-in/out, and Shift-click changes the curve. Zoom and
numeric crop/fade fields are available in the editor; Undo/Redo retains the earlier
state. Dragging an existing edge/corner does not open a new editor or move the clip.
MIDI grid clicks add notes; note bodies drag pitch/time, right edges resize length,
and selected-note controls edit pitch, beat, duration and velocity or delete a note.
These edits use the existing undo/save path and stop transport before applying.

Each audio track offers Input Monitor, also reachable from Audio & MIDI Settings
or Command-comma. Monitoring requests microphone permission and routes the system
input through that track's mixer/effects, respecting track mute/solo/volume. One
audio track can be monitored at a time; changing selected track does not reroute it.
The monitor level is independent, starts at 60%, and monitoring starts off each
launch. Graph-changing monitoring switches are disabled during recording/busy work.
Use headphones to avoid feedback. Hardware input choice is managed by macOS Audio
MIDI Setup in this update; individual hardware input/channel mapping is future work.

Audio & MIDI Settings opens Apple's native Bluetooth MIDI connection window,
lists MIDI sources and exposes input enable/refresh. Source additions/removals
attach/detach automatically; disconnects release held input notes. Network controls
show/enable the system MIDI session and its connection policy, plus open Audio MIDI
Setup for peer management. The existing policy is preserved unless explicitly
changed. These controls alter macOS's shared Network MIDI session, not a private
DBAL network. No audio is streamed over MIDI.

Native Mac is the focus of these new editors/settings. iPad legacy/pro workflows
remain available; shared note-selection cleanup and four-corner fade handling are
compatible with the iOS 15.4 deployment floor. Previous session formats and AU state
are retained. Native source is now preserved under native/DBALPocketStudio in the
DBAL DAW repository; the existing web prototype is unchanged.

Hardware microphone routing, Bluetooth/network peers and an actual AUv3 session
still need acceptance on the owner's Mac. Consult the current CI result for Apple
compilation and offline/edit logic checks; compilation is not a hardware pass.
