# PORTING.md — Amberol-rb porting ledger

This is the single, versioned record of what this port has and has not
done relative to upstream (`origin/main`, Rust/GTK4/Libadwaita). The
detailed, per-round evidence lives in `.reports/*.md`; this file is the
short index that must stay current. **Process rule**: any commit that
closes or opens an item named here, or in `.reports/*.md`, updates the
relevant entry in that same commit — not in a later audit round. A prior
round let two items (`PULSE_PROP_*` and the `i18n.rs` test port) drift
stale across five commits before a later audit caught it; see
`.reports/accountability-ensurance.md` for that finding. This file exists
so the next person does not have to re-derive the current state from
scattered report prose.

## Ported and driven

All upstream widgets, the GStreamer/GstPlay-backed playback pipeline, the
queue/shuffle/playlist model, cover art + waveform generation, settings
(JSON-backed — see gap below), MPRIS, inhibit-controller, i18n catalogue,
and `PULSE_PROP_*` startup properties. `test/drive_window.rb` exercises the
window, playback controls, queue, volume, waveform, search, selection mode,
and dialogs at the signal level (see `.reports/component-parity.md` for the
exact action list and `.reports/drive-run.md` for the current gate status).

## Known gaps (open)

1. **13 `C_("a11y", ...)` accessible name/description strings, 8 widgets**
   (elapsed/remaining-time labels, playlist search entry, queue-row cover
   placeholder + now-playing state, 7 playback-control buttons). Blocked on
   a ruby-gnome binding gap: `Gtk::Accessible#update_property` in the
   `gtk4` gem (v4.4.0) raises `NotImplementedError` for every argument
   shape tried (symbol, `Gtk::AccessibleProperty` enum value, array-of-enum,
   array-of-string) — confirmed directly against the installed gem, not
   inferred. Not worked around with a hand-rolled GI call. See
   `.reports/component-parity.md` Gap 1.

2. **Settings are a hand-written JSON file under `XDG_CONFIG_HOME`**
   (`lib/amberol/settings.rb`), not a compiled
   `org.rubygtkproject.Amberol.gschema.xml` + `Gio::Settings`. External
   tools (`dconf-editor`, `gsettings`) cannot read/set the 5 keys, and
   there is no schema-level default/range validation. Needs a shipped
   `data/*.gschema.xml`, a compile step, and a `settings.rb` rewrite onto
   `Gio::Settings`. See `.reports/component-parity.md` Gap 2.

3. **No XDG background-portal request** (`org.freedesktop.portal.Background`)
   from `app.background-play` — the port only takes/drops a
   `Gtk::Application` hold (`lib/amberol/application.rb`). Left out rather
   than hand-rolled against `Gio::DBusProxy` with no real
   `xdg-desktop-portal` available in this environment to verify the
   Request/Response round-trip against; an unverified D-Bus implementation
   would be a worse defect than the documented gap. See
   `.reports/component-parity.md` Gap 3.

4. **Runtime/UI driver gate**: a ruby-gnome binding-level crash,
   not a port logic bug (see below), has kept `test/drive_window.rb` from
   reaching a clean `DRIVE OK` in several recent rounds. See
   `.reports/drive-run.md` for the full run history.

5. **RSpec suite** covers only `lib/amberol/i18n.rb` (ported from
   `src/i18n.rs`'s test module). The rest of `lib/` has no spec coverage.
   See `.reports/test-parity.md`.

## The GstPlay worker-thread segfault (binding gap, not a port bug)

`GstPlay::Play` (the `gstreamer_play` gem, backed by gst-plugins-bad) runs
its pipeline on its own native worker thread (`gst_play_main`, spawned via
`g_thread_new`) — a thread Ruby's VM has never registered. When
`GstBackend#set_song_uri` swaps the live `playbin`'s URI during
`Player#switch_to`/`#skip_next` (faithful to upstream `src/audio/player.rs`,
which does the identical pause-then-set-URI sequence with no `stop()`
first), playbin3 teardown occasionally logs a `GStreamer-CRITICAL` message
from that worker thread. `ruby-gnome`'s installed default GLib log handler
(`rbglib_log_handler` in `glib2.so`) calls into the Ruby VM via
`rb_funcallv` for every GLib log message regardless of which thread emitted
it, and that call from an unregistered native thread segfaults.

This round re-investigated whether a pure-Ruby fix is possible (no port
code change, i.e. no C patch to ruby-gnome):

- `GLib::Log.set_handler(domain, level_mask, handler)` was tried with a
  no-op handler for the `"GStreamer"` domain. It still routes through the
  same `rb_funcallv`-based dispatch as the default handler — the crash
  mode is the GVL-unsafe dispatch mechanism itself, not which Ruby callback
  is attached, so installing a different handler through this API does not
  avoid the problem.
- There is no discovered Ruby-level API to remove or replace the *global*
  default handler that `glib2.so` installs at load time (the one that
  actually intercepts GStreamer's own `g_critical`/`g_warning` calls); the
  gem ships as a prebuilt extension here with no accessible C source to
  confirm an alternative registration path.
- No change to `lib/amberol/audio/player.rb`'s sequencing was made, because
  upstream's Rust backend does the identical sequencing (confirmed via
  `git show origin/main:src/audio/player.rs`) and reordering it here would
  be an invented, behaviour-changing workaround for a bug that is not in
  this port's logic.

Conclusion stands from the prior round: this is a `ruby-gnome`
(`glib2` gem) binding gap — the default log handler is not safe to invoke
from a thread the Ruby VM did not spawn — and needs a fix inside
`ruby-gnome` itself (e.g. routing cross-thread `g_log` calls through
`rb_thread_call_with_gvl`, or detecting a foreign thread and falling back
to the C default handler instead of calling into Ruby). It is tracked here
rather than patched around.
