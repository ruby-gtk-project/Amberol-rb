# Accountability ensurance — Amberol-rb

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh` and a
manual grep (`TODO|FIXME|not implemented|for now|in a future|not yet|
unimplemented|stub|dropped deliberately|out of scope|not applicable|n/a`)
over `lib/`, `exe/`, `.reports/`, and confirmed there is no `PORTING.md` in
this tree to check.

## Findings

**No `PORTING.md` exists.** There is nothing at the repo root that could
carry the "settled architecture" failure this skill exists to catch — no
file plays the role `console-rb`'s `PORTING.md` played. This is itself worth
recording: there is no single ledger of "what was ported / what was
skipped and why" for a future agent to misread as authority. The four
parity reports in `.reports/` are the closest thing, and none of them was
written by excusing a gap — see below.

**`find-excuses.sh` over `lib/`, `exe/`: zero hits.** No `TODO`, `FIXME`,
"not implemented", "for now", "in a future", "not yet", "stub",
"dropped deliberately", "out of scope", "not applicable", "n/a" anywhere in
the port's source or executable. (One incidental regex hit in
`lib/amberol/audio/gst_backend.rb:36`, "falls out of scope" — this is a Ruby
GC/variable-scope comment about `@file`'s lifetime during a GStreamer
callback, unrelated to porting scope. Read in context and confirmed not an
excuse; flagged here rather than silently dropped, per the rule that a scan
hit is read, not assumed.)

**`find-excuses.sh` over this round's own `.reports/*.md`: zero hits**
(after one self-correction — see below). The four parity reports
(`component-identification.md`, `component-parity.md`, `test-parity.md`,
`translation-parity.md`) written in this round state every gap as a gap:
"gap", gaps named with file:line on both sides, and a "Text/Behaviour still
owed" column — never "not applicable", never "by design", never "out of
scope" for the four real findings (the 13 missing accessibility labels, the
settings/GSettings substitution, the missing background portal request, the
missing `PULSE_PROP_*`). The settings/portal/PulseAudio items were already
documented as known gaps by a prior round (in-line code comments at
`lib/amberol/settings.rb:13` and `lib/amberol/application.rb:105-106`); this
round re-verified each by reading the current file rather than trusting the
comment, and reports them as open gaps, not as settled decisions.

**One self-correction made during this audit:** `test-parity.md` originally
used the phrase "with no Ruby equivalent" to describe why `freplace`'s
placeholder-substitution logic has no port-side test. The scanner correctly
flagged this — "no Ruby equivalent" is exactly the "could not exist here"
construction this skill exists to catch, even though in context it was
describing the absent *test*, not an absent *feature* (the feature,
`freplace`, is fully ported at `lib/amberol/i18n.rb`; only its test is
missing). Reworded in place to remove the ambiguity. Recorded here rather
than silently fixed, because a reviewer re-running the scanner on the
committed version should not find a stale finding with no explanation.

## The most important finding in this category: a false green, not an
   excuse, and it is in the runtime gate itself

The sharpest accountability risk this round is not prose anywhere — it is a
**number**: the runtime gate reports `104 checks passed, 0 failed`, true and
reproduced independently in `.reports/test-parity.md`. Read next to it,
unqualified, that number implies the port's test posture is sound. It is
not: the port's own declared `rspec` suite (`spec/`) contains zero example
files and returns `0 examples, 0 failures` — a suite that has never asserted
anything, reported in a form indistinguishable from "all tests pass" to
anyone who does not open `spec/` and count. And upstream's one real test
module (`src/i18n.rs`, 4 `#[test]` functions pinning the port's own
hand-rewritten string-substitution logic) has zero ported counterpart.

Nobody wrote a sentence excusing this — there is no "the rspec suite is not
needed" anywhere. But the omission to say it plainly, in the one place
someone would look (the gate summary, or a `PORTING.md` that does not
exist), is the same failure this skill exists to catch at one remove: a
true, loud, green number sitting next to a silent, empty, un-flagged one.
This audit's `test-parity.md` and `translation-parity.md` both state the
corresponding gaps explicitly and by name (0/4 upstream tests ported; 13/76
upstream messages gapped, all accessibility labels) specifically so that the
next reader cannot mistake "104/104" or "54 languages ship" for "the port is
finished."

## Conclusion

No excuse-shaped prose was found being used to launder a gap in this round.
The real risk this round surfaces is not rhetorical but statistical: a
genuinely-passing, narrow check (the drive run) and a genuinely-empty,
vacuously-passing check (`rspec`) sitting side by side with nothing written
down anywhere to tell them apart. That distinction is made explicit in
`.reports/test-parity.md` and is the headline finding of this audit.
