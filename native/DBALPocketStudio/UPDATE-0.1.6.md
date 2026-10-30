# 0.1.6 (build 7): Audio Unit discovery refresh

The previous iPad picker made one synchronous query when opened, ignored component
registration notifications and excluded every Apple unit. Its empty-list wording
incorrectly implied compatibility validation had occurred. This does not establish
why a particular installed third-party extension was missing on a physical iPad.

Both native Mac and iPad now use the same discovery path:
- Merge AVAudioUnitComponentManager results with AudioComponentFindNext registry
  results, deduplicating type/subtype/manufacturer rather than generated UUID.
- Rescan immediately, after each of three one-second delays, on registration-change
  notifications and on returning to the foreground. Dismissal cancels retries.
- Offer manual Refresh Audio Units while the list remains open.
- Show raw manager/registry entry counts and third-party instrument/effect counts.
- Keep Apple units available through an explicit toggle for baseline diagnostics.
- Include audio generators in the instrument category; retain effects and
  MIDI-aware music effects in the effect category. MIDI-only processors and IAA
  nodes remain outside this audio-hosting path.
- Exclude the private in-process Pocket FX implementation from hosted choices.

Discovery reads metadata only, never instantiates every installed plug-in or
modifies an existing session. Plug-ins still load asynchronously when selected.
No registry reset, extra App ID or new entitlement is required by this patch.

## Physical iPad acceptance
Save/export your session before updating the existing app. Preserve its bundle ID.
Open an instrument track's AU picker. Note the two discovery counts and third-party
category counts; tap Refresh if necessary. Repeat from + AU Effect. An effect-only
AU is not expected in the instrument list. If only Apple units appear, send the
counts and one missing plug-in name/version along with whether another host on the
same iPad sees it. This is evidence for extension registration visibility, not a
reason to keep reinstalling source projects or reopening containing apps.

For a discovered instrument, test loading, editor display, MIDI audition, project
save/reopen and WAV export. For an effect, use an audible audio track and test
bypass/removal and saved-state restoration. Third-party compatibility on iPadOS
15.4.1 still needs the physical device; Apple compilation and a local registered
metadata fixture do not establish that all installed AUv3s work.
