# Drive run — Amberol-rb

Ran the existing headless UI harness (`test/drive_window.rb` +
`test/gtk_driver.rb`, both already present on `ruby`) and the `rspec` suite,
per the `ruby-gtk-testing` skill, to prove the port actually opens a window
and responds to input rather than merely parsing.

## `rspec`

```
$ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'
17 examples, 0 failures
```

The 17 examples are `spec/amberol/i18n_spec.rb`, the port of upstream's one
test module (`src/i18n.rs`'s 4 `#[test]` functions) — closing the gap
`.reports/test-parity.md` recorded against the commit before this one.

## `test/drive_window.rb`

The harness drives the real window with real generated WAVE files, through
real `GstPlay::Play` playback (not stubbed), across ~38 steps covering the
window, primary menu, shortcuts dialog, about dialog, empty/junk-folder/
error states, real queue loading, play/pause, seek, a real end-of-stream
auto-advance, search filtering, shuffle, selection mode + removal, repeat
mode, previous/next/skip-to, cover-art recoloring, replaygain, volume mute,
waveform seek, toasts, copy/open-directory, the sidebar toggle, the add-song
and add-folder file choosers, the drag overlay, background-play, clear and
restore-playlist, and quit.

Four full runs were made this round. One (run 1) was ended early by an
external 170s wrapper timeout of my own choosing, not the harness — not a
failure, just inconclusive past the point it was cut off (every check up to
then passed). The other three:

| Run | Result |
|---|---|
| 2 | `[BUG] Segmentation fault` during step 22 (`win.previous/win.next and win.skip-to`) |
| 3 | Harness's own 180s watchdog fired after step 26 (`the waveform view accepts a seek position`); no further step ran |
| 4 | `[BUG] Segmentation fault` during step 20 (`removing the selected song drops the queue by one`) |

No run this round reached `DRIVE OK`. Per this round's instructions, the
crash is diagnosed below rather than hidden, loosened, or wrapped away.

### The crash: a ruby-gnome binding gap, not a port bug

Both segfaults carry the identical signature:

```
GStreamer-CRITICAL **: Padname '':src_N does not belong to element urisourcebin0 when removing
[BUG] Segmentation fault at 0x0000000000000030
...
libruby(rb_funcallv) <- glib2.so(rbglib_log_handler) <- libglib-2.0(g_log)
  <- libgstreamer(gst_element_remove_pad) <- libgstplayback(free_output_slot)
  <- ... <- libgstplay-1.0(gst_play_set_uri_internal/gst_play_stop_internal)
  <- libglib-2.0(g_main_loop_run) <- libgstplay-1.0(gst_play_main)
  <- libglib-2.0(g_thread_proxy) <- libc(start_thread)
```

`GstPlay::Play` (the `gstreamer_play` gem, wrapping gst-plugins-bad's
`GstPlay`) runs its pipeline on a **private worker thread** it spawns itself
(`gst_play_main`, via `g_thread_new`) — a thread Ruby's VM has never seen.
Both crashes happened while `GstBackend#set_song_uri` swapped the live
playbin's URI (`lib/amberol/audio/gst_backend.rb:95-101`), called from
`Player#switch_to`/`#skip_next` after a song change. Occasionally (a
genuine GStreamer-internal race during playbin3 teardown — not every URI
swap triggers it) that teardown logs a CRITICAL message from the worker
thread. Ruby-gnome's installed GLib log handler, `rbglib_log_handler`
(`glib2.so`), always tries to call back into the Ruby VM via `rb_funcallv`
to format/deliver that message — which segfaults when the calling thread is
not one Ruby's VM owns.

This is not a port-introduced ordering bug: `git show
origin/main:src/audio/player.rs` shows upstream's own `skip_next`/
`skip_previous`/`skip_to` do the exact same thing — pause, then
`self.backend.set_song_uri(Some(&song.uri()))`, no `stop()` first — so the
Rust code hits the identical GStreamer-internal race. It does not crash
there because Rust's GStreamer bindings never route a foreign thread's GLib
log message back into a managed runtime; `rbglib_log_handler` doing exactly
that is the gap.

I did not patch around this by changing `player.rb`'s sequencing (that would
diverge from the upstream behaviour it was ported from, for no logic reason)
or by silencing the `GStreamer` log domain (that would suppress a real
diagnostic channel to make a crash stop happening, which is exactly the kind
of invented, behaviour-changing workaround this round's instructions rule
out). The exact gap, for whoever picks this up: **ruby-gnome's default GLib
log handler (`rbglib_log_handler` in `glib2.so`) is not safe to invoke from
a native thread GStreamer/GstPlay spawned itself**, and that handler fires
unconditionally on any `g_log` call, including CRITICAL messages logged by
GStreamer's own internals during normal (if racy) teardown.

### Run 3's hang: not reproduced, not claimed as a bug

Run 3's 180s watchdog firing after step 26 was not reproduced in three
targeted isolated repros (one driving `copy`/`open-directory`/the file
choosers alone with no playback active, one chaining the full post-26 step
sequence with no playback active, one additionally starting real playback,
calling previous/next/skip-to, recoloring, replaygain, mute and waveform
seek first) — all three completed cleanly end to end. This machine was
running many other forks' concurrent GTK/Xvfb drive scripts at the time
(confirmed via `ps aux`); I cannot rule out resource starvation as the
cause and am not recording it as a port defect, only as unreplicated.

## What this means for `DRIVE OK`

I am not reporting `DRIVE OK`. Two independent runs crashed via the binding
gap above before reaching the end of the script; no run this round
completed all ~38 steps. The harness itself is unchanged (it already
existed on `ruby` before this round and needed no fixes to its own logic —
the component coverage gap check in the task is already satisfied by its
existing ~38 steps across every window/dialog/menu/action/shortcut the
component-identification report lists). No code in `lib/` was changed this
round: the one thing that fails is a native crash in a dependency, reached
by code that matches upstream's own sequencing, and per this round's
instructions that gap is named here rather than papered over.
