# Component parity — Amberol-rb

| | |
|---|---|
| Upstream | `main` @ `3830fbb` |
| Port | `ruby` @ `bb2d931` |
| Units with full (4-axis) parity | not all — see gaps below |

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

## Gap 4 — No `PULSE_PROP_*` set at startup (re-confirmed)

Upstream's `src/main.rs` sets the PulseAudio media-role/app-name properties so
the Sound panel labels the Amberol stream correctly; no equivalent call exists
in `lib/amberol.rb` or `exe/amberol`. **Verdict: gap** (re-verified, cosmetic
but real — the audio stream is unlabeled in the system mixer).

## Summary

| Gap | Axis | Severity |
|---|---|---|
| 8 widgets missing `C_("a11y", ...)` accessible name/description | text + behaviour | real — breaks screen-reader use of core transport controls |
| Settings are JSON, not GSettings | behaviour (external access) | real — pre-existing, documented in-line |
| No background portal request | behaviour | real — pre-existing |
| No `PULSE_PROP_*` | behaviour (cosmetic) | real — pre-existing |

Everything else checked against upstream's `.blp`/`.rs` files and driven
through `test/drive_window.rb` holds 4-axis parity. The port is substantial
and mostly correct; it is not yet at full component parity because of the
four gaps above, three of which were already known and one of which (the
accessibility labels) is new in this audit.
