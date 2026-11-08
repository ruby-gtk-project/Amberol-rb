# Test parity — Amberol-rb

| | |
|---|---|
| Upstream | `main` @ `3830fbb` |
| Port | `ruby` @ `5fc06dc` |
| Upstream tests | 4 |
| Ported | 4 |
| Gaps | 0 |
| Test command (port) | `nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'` |

**Correction to the previous round of this document:** it reported 0/4
ported and an empty `spec/` directory. Both are stale. Commit `e9f7ae4`
added `spec/amberol/i18n_spec.rb` (107 lines, 17 examples), closing all 4
gaps this document tracked. Re-run this round:

```
$ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","documentation","--require","spec_helper","spec"])'
17 examples, 0 failures
```

The 17 examples group into exactly the upstream module's 4 `#[test]`
functions (`describe` blocks named `i18n/ni18n (test_i18n)`,
`i18n_f/ni18n_f (test_i18n_f)`, `i18n_k/ni18n_k (test_i18n_k)`,
`pi18n/pni18n/pi18n_f/pi18n_k (test_pi18n)`), each with multiple `it`s
covering the same cases upstream's test pins (leading/middle/trailing
placeholder, repeated/reordered keywords, plural-count selection, context
threading). Not reported as a bare "4/4 closed, trust it" — re-run and
read above, not copied from the commit message.

## Census (ran `.claude/skills/test-parity/scripts/test-census.sh` on both
   trees, cross-checked against upstream's source directly)

Upstream has exactly **one** test module, `#[cfg(test)] mod tests` at the
bottom of `src/i18n.rs` (lines 132–215), with four `#[test]` functions. No
other `.rs` file in `origin/main` contains `#[test]` (verified: `git ls-tree
-r --name-only origin/main -- src | xargs -I{} sh -c 'git show
origin/main:{} | grep -l "#\[test\]"'` returns only `src/i18n.rs`). There is
no `tests/` directory and no test target beyond `cargo test`'s default
discovery.

## Suite: `src/i18n.rs` → `lib/amberol/i18n.rb` (4 tests)

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `test_i18n` | `i18n`/`ni18n` fall back to the msgid/plural-rule when no catalogue is bound | `spec/amberol/i18n_spec.rb` `i18n/ni18n (test_i18n)` (2 examples) | **ported** |
| 2 | `test_i18n_f` | `i18n_f`/`ni18n_f` substitute positional `{}` placeholders, stopping at the shorter of args/placeholders | `spec/amberol/i18n_spec.rb` `i18n_f/ni18n_f (test_i18n_f)` (5 examples) | **ported** |
| 3 | `test_i18n_k` | `i18n_k`/`ni18n_k` substitute `{name}` placeholders, including repeated and reordered names | `spec/amberol/i18n_spec.rb` `i18n_k/ni18n_k (test_i18n_k)` (6 examples) | **ported** |
| 4 | `test_pi18n` | `pi18n`/`pni18n`/`pi18n_f`/`pi18n_k` apply a msgctxt and otherwise behave like the unprefixed forms | `spec/amberol/i18n_spec.rb` `pi18n/... (test_pi18n)` (4 examples) | **ported** |

All four of upstream's test cases, for the one piece of upstream logic that
was *rewritten from scratch* in Ruby (`i18n.rs`'s own string-substitution
code, not a GTK/GLib call — exactly where a silent behavioural drift was
most likely), now have a port-side counterpart, confirmed green this round
(`17 examples, 0 failures`, reproduced above, not merely read from the
commit that added them).

## Does the suite that exists actually run?

Yes, as of this round. `spec/` now contains `spec/amberol/i18n_spec.rb`
alongside `spec/spec_helper.rb`. Running the port's own declared spec
command (reproduced above): `17 examples, 0 failures`. This is a suite that
executes and exercises real logic (`freplace`/`kreplace`/plural selection in
`lib/amberol/i18n.rb`), not a vacuous pass — confirmed by reading the spec
file's assertions, not just the example count.

## `test/drive_window.rb` — Extra, outside the 4/4 count, and the live false-green risk this round

`test/drive_window.rb` is not a port of any upstream test — upstream has no
UI test harness at all, nothing under `src/` builds or drives a window in a
test — so it stays `## Extra` regardless of outcome and cannot close or
reopen any of the 4 rows above. But its outcome matters to how the *overall*
gate should be read, and this round it is the opposite of the previous
round's: previously it ran clean (`104/104`, `DRIVE OK`); this round, per
`.reports/drive-run.md`, **two of four runs segfaulted mid-script and zero
runs reached `DRIVE OK`** (a ruby-gnome GLib-log-handler crash on a native
GStreamer thread, diagnosed there in full; not a regression introduced by
this round's `lib/` changes — `lib/` was not touched this round — but a
pre-existing native-dependency fragility that a prior, shorter-lived run
simply didn't hit).

## Reading the runtime gate against this ledger

The task's stated gate for this round is `drive_ok=false, 104 checks passed,
0 failed, covering 21 components`. Read uncritically, `0 failed` sounds
clean; it is not. `drive_ok=false` is the operative fact, and
`.reports/drive-run.md` explains why: the checks that *did* execute before a
run crashed or hit a watchdog all passed, but no run completed the script,
so "0 failed" describes a partial, truncated execution, not a clean one. The
most important thing this report can do is say that plainly rather than let
`104 checks passed, 0 failed` read as a pass on its own — the exact shape of
false green the previous round warned about when the two numbers were
`104/104` + `0/4 ported tests`. That specific pairing is now closed (4/4
ported, above); the new pairing to watch is `104 passed / 0 failed` sitting
next to `drive_ok=false` — a genuinely-reported, not-explained-away failure
this time, which is the right outcome, not a gap in the reporting.

## Rules check

- No gap row is lowered or merged: 4 upstream tests, 4 rows, 4 **ported**
  (re-verified by running the suite, not by reading the diff).
- No test was made to pass by weakening it.
- The drive run's `## Extra` status, and its failure to reach `DRIVE OK`
  this round, are stated plainly per the skill and are not counted toward
  or against the 4/4 test-parity figure above.
