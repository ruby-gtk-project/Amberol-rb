# Accountability ensurance — Amberol-rb

| | |
|---|---|
| Upstream | `main` @ `3830fbb` |
| Port | `ruby` @ `5fc06dc` |

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh` and a
manual grep (`TODO|FIXME|not implemented|for now|in a future|not yet|
unimplemented|stub|dropped deliberately|out of scope|not applicable|n/a`)
over `lib/`, `exe/`, `.reports/`, and confirmed there is still no
`PORTING.md` in this tree to check.

## Findings

**No `PORTING.md` exists.** Unchanged from the previous round. There is
still no single ledger of "what was ported / what was skipped and why" at
the repo root; the five reports in `.reports/` remain the closest thing.

**`find-excuses.sh` over `lib/`, `exe/`: zero hits**, re-run this round. No
`TODO`, `FIXME`, "not implemented", "for now", "in a future", "not yet",
"stub", "dropped deliberately", "out of scope", "not applicable", "n/a"
anywhere in the port's source or executable. (The same incidental hit as
last round, `lib/amberol/audio/gst_backend.rb:36`'s "falls out of scope" —
a Ruby GC/variable-scope comment, unrelated to porting scope — re-checked
in context, still not an excuse.)

**`find-excuses.sh` over this round's updated `.reports/*.md`: 11 hits, all
false positives, read and confirmed, not assumed away.** Running the
script against `.reports/` (rather than just `lib/`/`exe/`) flags this file
itself — `accountability-ensurance.md` — on phrases like "dropped
deliberately", "out of scope", "not applicable", "by design", "skipped".
Every hit is this document *naming the scanner's own pattern list* (the
paragraph above quotes it verbatim) or *describing*, not *using*, those
constructions (e.g. "what was ported / what was skipped and why" in the
PORTING.md paragraph; "unrelated to porting scope" quoting last round's own
gst_backend.rb finding; "is the one place... un-excused" in the drive-gate
section). None of the four other reports
(`component-identification.md`, `component-parity.md`, `test-parity.md`,
`translation-parity.md`) trips the scanner at all. Recorded here rather
than silently excluding this file from the scan, per the rule that a hit
is read in context, not assumed to be either a real excuse or a false
positive without checking.

## The headline finding this round: three reports had gone stale, and sat
   that way across five commits before this audit caught it

This is the central accountability finding of this round, and it is a
different shape from last round's. Last round's reports
(`component-identification.md`, `component-parity.md`, `test-parity.md`,
committed at `a3f2616`, port HEAD `bb2d931`) correctly recorded 4 open
items: 13 missing a11y labels, JSON-not-GSettings, no background-portal
request, no `PULSE_PROP_*`, and 0/4 ported upstream tests. Five commits
later (`34f281f` through `5fc06dc`), two of those were closed by real work —
`e9f7ae4` added `PULSE_PROP_*` at startup **and** ported all 4 upstream
`i18n.rs` tests as `spec/amberol/i18n_spec.rb` — but **none of the three
affected reports was updated to say so.** Until this audit, a reader of
`component-parity.md` or `test-parity.md` would have read "gap" / "0/4
ported" on a port that had already closed those exact items days of commits
earlier. That is not an excuse written into prose (the `find-excuses.sh`
scan correctly finds nothing, because nobody wrote a sentence rationalizing
anything) — it is the same failure one level up: paperwork that stopped
being re-verified against the code it describes, which is indistinguishable
from a true "still open" claim unless someone actually re-reads the current
file, as this round did (see the "correction" notes now in
`component-identification.md`, `component-parity.md`, and
`test-parity.md`). Fixed in this round by re-reading every claim against
current `HEAD` rather than trusting the previous round's prose, and by
naming each correction explicitly in place rather than silently editing the
number.

This cuts in the accurate direction (gaps that were stale-closed, not
gaps that were stale-hidden), which is the less dangerous of the two ways a
report can drift — but a reporting process that only happens to drift
safely is still a reporting process that drifted, and the next drift might
not be safe. **Recommendation carried forward, not fixed by this round**:
any commit that closes an item named in `.reports/*.md` should update that
report in the same commit, or at minimum the same session, rather than
leaving the correction to the next audit.

## The runtime gate: `drive_ok=false, 104 checks passed, 0 failed` — a real
   failure, correctly reported as one, not a false green

This round's gate is the opposite shape from last round's. Last round's
gate was `drive_ok=true, 104/104, 0 failed` sitting next to an empty `rspec`
suite — a false green, because the full number implied a test posture that
did not exist. This round, `rspec` is real (17/17, see `test-parity.md`),
but the UI driver gate itself is `drive_ok=false`: `.reports/drive-run.md`
documents four actual runs this round, two of which **segfaulted mid-script**
(a ruby-gnome GLib-log-handler crash on a native GStreamer worker thread,
root-caused there to the `glib2.so` log handler, not to any port-introduced
ordering bug — confirmed against upstream's own `src/audio/player.rs`,
which does the identical sequencing), one of which hit its own 180s
watchdog, and one of which was cut off by an external timeout before any
check failed. **Zero of four runs reached `DRIVE OK` this round.**

Read uncritically, `104 checks passed, 0 failed` sounds clean next to
`drive_ok=false`; the risk is exactly that someone reads the two passing
numbers and skips over the boolean. This audit confirms `drive-run.md`
already does the right thing here: it states plainly that no run finished,
names the crash by stack trace and root cause, declines to paper over it
by loosening the harness, changing `player.rb`'s sequencing to dodge the
race, or suppressing the `GStreamer` log domain to stop the crash from
being visible — any of which would have been the behaviour-changing,
rule-violating workaround this skill exists to catch. **This is the one
place in the whole audit where a genuinely bad number is reported as a
genuinely bad number, un-excused**, and it is called out here as the
correct behaviour to hold the line on, not a gap to fix in the report.

## Conclusion

No excuse-shaped prose was found laundering a gap in this round, in either
`lib/`/`exe/` or `.reports/`. The real finding this round is procedural: the
previous round's reports drifted out of sync with the code across five
intervening commits, on two separate items, and stayed that way until this
audit re-verified every claim against current `HEAD` instead of trusting
the prose. Both drifted toward "we fixed it, but didn't say so" rather than
toward "we broke it, but didn't say so" — the safer direction, but not a
reason to treat report staleness as low-risk going forward. The runtime
gate's `drive_ok=false` this round is a real, unresolved failure
(`.reports/drive-run.md`), correctly reported as a failure rather than
excused, and is the headline open item of this entire audit, not a
reporting defect.
