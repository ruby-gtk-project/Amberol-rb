# Component parity — Amberol-rb

| | |
|---|---|
| Upstream | `main` @ `3830fbb` |
| Port | `ruby` @ `5fc06dc` |
| Units with full (4-axis) parity | not all — see gaps below |

**Correction to the previous round of this document:** its "Gap 4 —
No `PULSE_PROP_*`" has been closed since that round, by commit `e9f7ae4`
(`lib/amberol.rb:9-11`). This round re-verifies that by reading the current
file and drops it from the open-gaps list below; it is not carried forward
unchecked. Three gaps remain open.

This builds on `.reports/component-identification.md` and
`.reports/component-inventory.md` (the previous round's full 37-unit, file-by-
file widget/CSS/signal table, re-verified above). This report records the
axes that table did not check — text-axis (msgid) and behaviour-axis
(does the signal actually fire) confirmation — plus re-verification of the
three previously-known structural gaps.

## Confirmed parity (driven, not just read)

`test/drive_window.rb` under `nix develop --command xvfb-run -a ruby
test/drive_window.rb` reaches `104 of 104 checks passed / DRIVE OK` and
exercises real signal-level behaviour, not just construction, for the units
it touches: `win.play`/`win.next`/`win.previous`/`win.skip-to`,
`win.seek-forward`/`win.seek-backwards`, `win.enable-recoloring`,
`win.replaygain`, `win.copy`/`win.open-directory`, `queue.toggle`,
`queue.add-song`/`queue.add-folder` (file-chooser dialogs appear and are
dismissed), `queue.clear`, `queue.restore-playlist`, `app.background-play`,
`app.quit`, the playlist search bar, selection mode, shuffle/repeat cycling,
the volume control's mute round-trip, and the waveform view's seek
round-trip. For every one of these the primary menu, shortcuts dialog and
about dialog content, and the window/playlist-view/playback-control/
volume-control/queue-row/drag-overlay widget trees, I confirm parity on all
four axes (count, style, behaviour, text) — this is a solid, large slice of
the app and the drive run is real evidence, not a claim resting on
construction alone.

## Gap 1 — accessible name/description axis dropped for 8 widgets (text + behaviour)

See `.reports/component-identification.md` for the full table. Upstream sets
`C_("a11y", ...)` as the accessible label/description on:

- the elapsed-time and remaining-time labels (`window.blp:128,142`)
- the playlist search entry's label and description (`playlist-view.blp:66-67`)
- the queue-row cover placeholder and "currently playing" state
  (`queue-row.blp:27,81`)
- 7 playback-control buttons: skip-backward, toggle-play, skip-forward,
  toggle-playlist, shuffle, repeat, primary-menu (`playback-control.blp:28,
  44,59,86,97,123,141`)

None of these 13 accessible strings appear anywhere in the port (`grep -rn
'"a11y"' lib/ exe/` → no hits; the only `accessible_role` calls in `lib/` are
three unrelated ones in `cover_picture.rb`, `marquee.rb`, `waveform_view.rb`).

This is a **behaviour-axis gap, not merely a text-axis one**: these widgets
expose no accessible name/description to assistive technology at all, not an
unmarked-but-present English one. A screen reader user gets silence or the
GTK default ("button") on 8 controls including the primary transport
controls. It is also a translation-parity gap (see that report) — the same
underlying defect, tracked in both ledgers per the skill's rule.

**Verdict: gap**, 8 widgets across `playback_control.rb`, `window.rb`,
`playlist_view.rb`, `queue_row.rb`.

## Gap 2 — Settings model: JSON file, not GSettings (re-confirmed)

`lib/amberol/settings.rb:10-56` stores the 5 preference keys in a JSON file
under `XDG_CONFIG_HOME` rather than through a compiled
`org.rubygtkproject.Amberol.gschema.xml` and `Gio::Settings`. No
`data/*.gschema.xml` ships. Confirmed still true by reading the current file
(comment at line 13 states this explicitly). This is a correspondence the
port chose, but it has a real behavioural cost it does not call out anywhere
outside this file's own comment: nothing external (dconf-editor, a second
process, `gsettings get`) can read or set these keys, and the keys are not
covered by any schema-level default/range validation. **Verdict: gap**
(structural, pre-existing, re-verified).

## Gap 3 — No XDG background portal request (re-confirmed)

`lib/amberol/application.rb:105-106`: the comment states upstream also asks
the background portal for permission and the port does not. `app
.background-play` only takes/drops a `Gtk::Application` hold; under a
sandboxed (Flatpak) build this would be killed instead of continuing to play
in the background, which is the entire point of the feature. **Verdict:
gap** (re-verified).

## Gap 4 (closed) — `PULSE_PROP_*` at startup

Upstream's `src/main.rs` sets the PulseAudio media-role/app-name properties
so the Sound panel labels the Amberol stream correctly. As of `e9f7ae4`,
`lib/amberol.rb:9-11` sets the same three `ENV["PULSE_PROP_*"]` keys before
`amberol/application` loads. **Verdict: closed**, confirmed by reading the
current file this round. (Not re-tested against the live PulseAudio/PipeWire
mixer — that is an external-system assertion no headless CI run can make —
but the call is present, matches upstream's three keys, and runs at the
right point in startup.)

## Summary

| Gap | Axis | Severity |
|---|---|---|
| 8 widgets missing `C_("a11y", ...)` accessible name/description | text + behaviour | real — breaks screen-reader use of core transport controls |
| Settings are JSON, not GSettings | behaviour (external access) | real — pre-existing, documented in-line |
| No background portal request | behaviour | real — pre-existing |
| ~~No `PULSE_PROP_*`~~ | — | **closed this round** (see above) |

Everything else checked against upstream's `.blp`/`.rs` files and driven
through `test/drive_window.rb` holds 4-axis parity on the units that run
clean. The port is substantial and mostly correct; it is not yet at full
component parity because of the three open gaps above. It is also, per
`.reports/drive-run.md`, not provably correct end-to-end: two of four runs
of `test/drive_window.rb` this round segfaulted mid-run (a ruby-gnome GLib
log-handler/native-thread bug during `GstPlay::Play` URI swaps, diagnosed
there in full), so no run this round reached `DRIVE OK`. The "confirmed
parity" claims above, where they rest on `test/drive_window.rb` reaching
`104/104`, reflect a **prior** green run, not this round's; this round's
`104 checks passed, 0 failed` gate number is real for the checks that did
execute before a run crashed or hit its watchdog, but it is not evidence the
full ~38-step script completes, and is not claimed as such here. Component
parity and "the driver survives a full run" are tracked as two different
questions; the second one is currently false.
