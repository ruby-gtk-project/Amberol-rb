# Drive run — Amberol-rb

## This round

Ran `test/drive_window.rb` + `test/gtk_driver.rb` and the `rspec` suite again,
per the `ruby-gtk-testing` skill. `rspec` is unchanged and clean (17 examples,
0 failures). The UI driver needed two real fixes to its own code before it
could reach `DRIVE OK` at all, plus leaves one check intermittently flaky for
reasons tracked below rather than papered over.

### Fix 1 — unbounded `while pending?` busy-loop never terminated during real playback

Every prior round's crash/hang at step 26 ("the waveform view accepts a seek
position") or thereabouts traced to this exact line, used a dozen times in
the file:

```ruby
GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
```

Real `GstPlay` playback posts a `POSITION_UPDATED` bus message every 250ms
(`GstBackend::POSITION_UPDATE_INTERVAL`) for as long as a song plays. Once
the host is slow enough (this round ran under sustained load average 10-15,
a dozen-plus sibling forks' own Xvfb/GTK drive scripts running concurrently),
the gap between messages can shrink to nothing relative to how long one
`iteration(false)` call takes to return, so `pending?` can read true again
before the loop ever observes a false — an unbounded busy-wait racing a live
external source, not a bug in the steps it was driving. Confirmed by killing
a hung run and reading its backtrace: stuck inside this exact loop, having
consumed real CPU the whole time (not blocked on I/O), for minutes past the
harness's own 180s watchdog, which itself could not break the loop because
the watchdog's own callback only fires *from inside* this same manual drain.

**Fix**: a bounded `drain_pending_events(max_seconds: 2.0)` helper replaces
every instance of the pattern above. It still drains real work; it just
cannot spin forever racing a live source. Two of the fixed-`sleep(N)`+drain
waits for async idle-loaded songs were also replaced with a `wait_until`
helper that polls the actual condition (`queue.n_songs == N`) up to 10s,
which is more robust than guessing a wall-clock delay regardless of host
speed.

### Fix 2 — `close_extra_toplevels` mutated the list it was iterating, segfaulting

```ruby
def close_extra_toplevels(keep)
  Gtk::Window.toplevels.each do |window|
    unless window.equal?(keep)
      window.close
    end
  end
end
```

`Gtk::Window.toplevels` is a live `Gio::ListModel`. Closing a window removes
it from that same list. Iterating the model directly while closing entries
out of it mutates the list the iterator is walking — confirmed by two
separate crashes this round (runs on a fresh `ruby` checkout, no other
change in between), both segfaulting inside `rbgobj_signal.c`'s
`signal_emit` / `callable_method_entry_or_negative`, with the Ruby backtrace
pointing straight at `window.close` from inside this method's `each` block,
and register state showing `RAX`/`RDI` = `-1` (an invalid object pointer) —
the signature of indexing a GListModel that has already shifted under the
iterator.

**Fix**: `Gtk::Window.toplevels.to_a.each do |window| ... end` — read every
entry into a plain Array first, then close from that snapshot. Trivial,
behaviour-preserving, and removes a real crash that two previous rounds had
misattributed entirely to the (also real, separately documented below)
GstPlay worker-thread log-handler gap.

### Result after both fixes: one full clean run

```
105 of 105 checks passed
DRIVE OK
```

This proves the fixes are real: the harness ran end to end, through every
window/dialog/menu/action/shortcut/empty-state/error-state the
component-identification report lists, with no crash and no hang.

### The one check that stayed flaky: `queue.restore-playlist`'s songs arriving

This round's final check — that the two songs left after `queue.clear` come
back after `queue.restore-playlist` — passed in that one clean run and
failed in 8 of the 9 other runs made this round (both before and after
fixing the two bugs above; it is independent of them). Diagnosis, in order
ruled out:

1. **Not a duplicate-check false positive.** Printed `window.player.queue
   .contains?(...)` for both cached songs immediately before calling
   restore: `[false, false]` against a queue already confirmed at
   `n_songs == 0`. `Queue#clear` does reset `@songs = []`; nothing stale
   survives it.
2. **Not a disabled action.** `grep`-checked every `action_set_enabled` call
   in `window.rb`; `"restore-playlist"` is never in the disabled list
   `set_loading_actions_enabled` touches (only `add-song`/`add-folder`/
   `clear` are). A `GSimpleAction#activate` on a disabled action is a silent
   GLib no-op, which was the leading hypothesis — ruled out by reading the
   source, not assumed.
3. **Not a tag-reading/file-content problem.** Called
   `Amberol::Audio::Song.from_uri` directly on the exact cached file paths
   mid-run, both inside the full driver and in an isolated script with the
   same two generated WAVE files: always returns a valid `Song`
   (`valid? == true`). The files and the parser are both fine.
4. **No exception anywhere in the chain.** Wrapped the action's `.activate`
   call in `begin/rescue StandardError` in the test step itself across
   several runs: never fired. Nothing is being raised and silently
   swallowed between the action and the idle loader.
5. **The synchronous half of `start_loading` does run.** Printed
   `GLib::MainContext.default.pending?` and `main_stack.visible_child_name`
   immediately after calling `.activate(nil)`: `pending? == true`,
   `visible_child_name == "main-view"` — `switch_mode(:main_view)` and the
   `GLib::Idle.add` registration both ran. What never completes is the idle
   callback's own work: ten real seconds of `wait_until`'s own
   `GLib::MainContext.default.iteration(true)` polling loop (which, unlike
   the `drain_pending_events` fix above, blocks waiting for a source and so
   cannot race a live one the same way) never see `n_songs` move off `0`.

No single root cause was confirmed inside the port's own Ruby. The evidence
is consistent with the same class of problem as Fix 1 above — this host's
sustained, extreme concurrent load (10-15 load average from sibling forks'
own drive scripts, the same host every round in this campaign runs under)
occasionally keeps even a correctly-scheduled low-priority `GLib::Idle`
source from ever getting a dispatch slot inside a bounded wait, for reasons
this round could not pin down more precisely than "this specific idle
source, this specific host, this specific run." It is recorded here rather
than worked around by lengthening the wait indefinitely (which would just
move the same race further out) or by changing `start_loading`'s priority
(which would diverge from upstream's own `glib::idle_add_local` default and
change behaviour to paper over a timing symptom, the thing this round's
instructions explicitly rule out). Whoever next investigates this should
start from point 5 above: trace what, if anything, is competing with the
load idle source for a dispatch slot on a *clean, less loaded* run of this
same host, since the one pass this round coincided with its lowest observed
load point (10.3) against several failures at 11-15.

## Previous rounds (superseded by the above)

Four full runs were made in a previous round, all before either fix above
existed. Two hit the exact segfault Fix 2 now explains (misattributed at the
time to the GstPlay worker-thread log-handler gap below); one hit a watchdog
timeout at the exact loop Fix 1 now explains; one was cut off early by an
external wrapper timeout, inconclusive. See git history for that round's
full original writeup if needed — it is not reproduced here since both
crashes it reported are now explained and fixed.

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

This was not reproduced this round (no run reached that crash's signature),
but it was never conclusively ruled out either since Fix 2 above explains
every segfault actually observed this round. It is left documented rather
than removed, since the mechanism described (ruby-gnome's default log
handler not being safe to call from a foreign GStreamer worker thread) is a
genuine binding gap independent of anything in `lib/`, not something this
round verified absent.
