# Pocket Studio 0.1.1 — multi-clip selection and transport controls

## Build/update

This full source release includes all four compiler fixes established while compiling 0.1.0: leading-zero float literal, CoreAudioKit import, explicit non-async scheduleFile overload, and local variables for plugin-state assignment. The same application bundle identifiers and session schema are used.

Extract this folder, then in Terminal run:

```bash
cd ~/Downloads/DBAL-Pocket-Studio-0.1.1
bash Scripts/build_unsigned_ipa.sh Legacy
```

On success, Finder reveals `Build/PocketLegacy-0.1.1-unsigned.ipa`. Install it with the same Sideloadly account and bundle-ID settings as the working installation. Export your current sessions first. Installing with a different bundle identifier creates a separate app with a separate document store. Do not uninstall the existing app to update it.

`PocketLegacy` and `PocketPro` schemes and their Catalyst configurations remain available in DBALPocketStudio.xcodeproj.

## Multi-clip selection

Select is the default drag tool. With a mouse/trackpad, press and hold the primary button and drag a rectangle across audio clips. With a finger or Pencil, hold briefly (0.28 seconds) then drag; a quick swipe scrolls. Clips intersected by the rectangle highlight cyan across audio tracks. MIDI notes are not included.

Release opens an edit popover: Copy, Cut, Paste at Cursor, Duplicate Group After Selection, Split Selected at Cursor, Add 10 ms Edge Fades, Remove Edge Fades, Delete Selected and Clear Selection. The Edit N Clips menu below the timeline provides the same actions. Clip Editor is enabled only for one selected clip.

Enable Add to extend the selection with another rectangle or toggle individual clips by tapping them. This also supports nonadjacent groups. There is no edge auto-scroll during a marquee drag in this release; scroll between selections and use Add for clips outside the current viewport.

Choose Move to drag the selected group along the timeline. Relative spacing stays intact; snap follows the dragged clip's start and moving left clamps the entire group at beat zero. Each group action creates one undo checkpoint. Copy does not create an undo step. The clipboard survives Cut and undo/redo inside a session and clears on new/open. Paste uses the original source tracks at the current cursor, keeping relative timing and source offsets; if a source track was deleted, undo that track deletion first.

Duplicate places the whole group immediately after its latest end, preserving gaps across tracks. Split affects only selected clips containing the cursor. Fades are clamped to half the clip duration. Original audio assets are never deleted by these edits.

## Top controls

The top transport is now two compact rows:

- Play → Stop → Record → **Count-in** → Counter → Tempo
- Snap → Grid denominator → **Undo → Redo** → Loop → Click

Count-in cycles Off → 1 Bar → 2 Bars → Off. It is also reflected in the existing Settings pre-roll control and remembered across launches. Count-in ticks sound even when Click is off; Click controls the ongoing playback/recording metronome. Undo and Redo have dedicated arrow buttons and accessibility labels in the requested position.

## Verification

The creation environment has no Apple SDK or Swift compiler. Project structure, source inclusion, resource metadata and portable C sampler sanitizer tests passed. A new Swift regression test exercises marquee hit testing and group-edit math; run `bash Scripts/test_clip_edits.sh` on the Mac. It has not been executed here. This release's Swift build, new gestures/popover, group undo/redo and audible count-in still require Mac/iPad validation. The earlier 0.1.0 build was reported by the user to compile after the included fixes and to record successfully; that does not validate the new UI.
