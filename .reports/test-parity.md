# Test parity — Amberol-rb

| | |
|---|---|
| Upstream | `main` @ `3830fbb` |
| Port | `ruby` @ `bb2d931` |
| Upstream tests | 4 |
| Ported | 0 |
| Gaps | 4 |
| Test command (port) | `nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'` |

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
| 1 | `test_i18n` | `i18n`/`ni18n` fall back to the msgid/plural-rule when no catalogue is bound | — | **gap** |
| 2 | `test_i18n_f` | `i18n_f`/`ni18n_f` substitute positional `{}` placeholders, stopping at the shorter of args/placeholders | — | **gap** |
| 3 | `test_i18n_k` | `i18n_k`/`ni18n_k` substitute `{name}` placeholders, including repeated and reordered names | — | **gap** |
| 4 | `test_pi18n` | `pi18n`/`pni18n`/`pi18n_f`/`pi18n_k` apply a msgctxt and otherwise behave like the unprefixed forms | — | **gap** |

**Behaviour still owed**, per row:

1. `Amberol::I18n.i18n`/`ni18n` must return the input string (singular) /
   apply the Germanic plural rule, when no catalogue is bound — exactly what
   `lib/amberol/i18n.rb`'s `gettext`/`plural` private methods implement, and
   exactly what has no test today.
2. `Amberol::I18n.i18n_f`/`ni18n_f`'s `freplace` must zip `{}` placeholders
   against positional args and leave a trailing `{}` untouched when args run
   out — this is a genuinely fiddly piece of logic (`lib/amberol/i18n.rb`'s
   `freplace`, lines ~103-112) and it is exactly the kind of thing upstream
   wrote this test to pin down; the port has nothing pinning it down at all.
3. `Amberol::I18n.i18n_k`/`ni18n_k`'s `kreplace` must substitute every
   `{name}` occurrence, including a name used twice and two names used in
   either order — untested.
4. `Amberol::I18n.pi18n`/`pni18n`/`pi18n_f`/`pi18n_k` must thread a context
   through to the backend the same way as the unprefixed calls — untested.

All four gaps sit on the one piece of upstream logic that was *rewritten from
scratch* in Ruby (`i18n.rs`'s own string-substitution code, not a GTK/GLib
call) rather than carried over by the binding — which is exactly where a
silent behavioural drift is most likely and exactly what upstream's test
module exists to catch. None of it is ported.

## Does the suite that exists actually run?

`spec/` contains exactly one file, `spec/spec_helper.rb` — no `*_spec.rb`
anywhere in the tree. Running the port's own declared spec command:

```
$ nix develop --command xvfb-run -a ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format","progress","--require","spec_helper","spec"])'
NOTE: kettle-test isn't installed; running with plain RSpec.
No examples found.
0 examples, 0 failures
```

**This is a suite that has never been executed, because there is nothing in
it to execute.** `0 examples, 0 failures` is not evidence the port works; it
is evidence nothing was asked. Reporting this as a passing spec suite — or
leaving it uncommented so a reader assumes `rspec` covers something — would
be a false green, and it is called out explicitly here and in
`.reports/accountability-ensurance.md`.

## `test/drive_window.rb` — Extra, outside the count

37 driven scenarios, 104 `d.check(...)` assertions, confirmed green under
`nix develop --command xvfb-run -a ruby test/drive_window.rb` →
`104 of 104 checks passed / DRIVE OK`. This is real, substantial,
UI-integration-level coverage (actions, dialogs, menus, shuffle/repeat,
search, selection mode, drag overlay, restore-playlist, etc. — the "18
components" the runtime gate counts). It is **not** a port of any upstream
test — upstream has no UI test harness at all, nothing under `src/` builds or
drives a window in a test, and none of the 104 checks maps to one of the 4
upstream `#[test]` functions. It stays listed here as `## Extra` and does
not close any of the 4 gaps above; a suite can be large, green, and driven
headlessly and still have inherited none of the one piece of knowledge
upstream actually chose to pin down.

## Reading the runtime gate against this ledger

The round's gate reports `drive_ok=true, 104 checks passed, 0 failed,
covering 18 components`. That gate is real (reproduced above) and it is
good, substantial coverage of UI behaviour — but it answers a different
question than test parity does. It says nothing about whether
`Amberol::I18n`'s own substitution logic — the one piece of this app's string
handling that upstream wrote down regression tests for — behaves the same
as `src/i18n.rs`. By this skill's definition the gate does not close any of
the 4 gaps, and a 104/104-passing drive run coexisting with 0/4 ported
upstream tests and an empty `rspec` suite is exactly the "false green"
shape this audit was asked to look for: a loud, verified pass on one axis
standing next to a silent, unexercised axis right beside it.

## Rules check

- No gap row is lowered or merged: 4 upstream tests, 4 rows, 4 gaps.
- No test was made to pass by weakening it — there is nothing to weaken; the
  gap is absence.
- The 104 drive checks are listed under `## Extra`/this report's own section,
  outside the 4/4 count, per the skill.
