# Component identification — Amberol-rb

Scope: the whole app, one unit per upstream top-level widget/class (as
`.reports/component-inventory.md` from the previous round already enumerates
in detail — 37 units, file-by-file, with widget/CSS/signal tables). This pass
re-walks that inventory against the current `ruby` HEAD (`bb2d931`) and
upstream `origin/main` (`3830fbb`), and records what changed and what that
inventory did not catch.

## What is still accurate

All 37 units in `.reports/component-inventory.md` still map 1:1 to a `lib/`
file and the mapping is unchanged since that document was written. Spot
checks against upstream `origin/main` confirm the widget trees described
there (window, playback-control, playlist-view, queue-row, shortcuts-dialog,
song-cover, song-details, volume-control, marquee, waveform-view,
cover-picture, drag-overlay, primary-menu) are still structurally faithful:

- `Adw.Breakpoint` (`max-width: 560sp`, collapses `split_view`) — ported in
  `lib/amberol/window.rb:33,527-531`.
- The primary menu's 5 sections (Copy/Open Directory; Add Song/Add
  Folder/Clear; Match Cover Art/Background Playback; ReplayGain submenu;
  Shortcuts/About/Quit) — ported verbatim in `lib/amberol/primary_menu.rb`.
- The shortcuts dialog's 3 sections / 15 items — ported in
  `lib/amberol/shortcuts_dialog.rb` (18 `pi18n("shortcut window", ...)`
  call sites: 15 items + 3 section titles).

## What the previous inventory's "Remaining work" section got overtaken by

- **"No translations"** (item 36, "no") is now stale: `po/` was ported wholesale
  in commit `1b82a42` (54 languages, byte-identical `.po` files, compiled
  `.mo`s committed). See `.reports/translation-parity.md` for the real
  state, which is not simply "done" either — the catalogue ships, but 13
  upstream messages (all of them accessibility labels) are never produced by
  the port's source.

## A component-identification gap this inventory's summary table does not
   surface: accessible names/descriptions as components in their own right

Upstream's `.blp` files set `C_("a11y", "...")` on 8 widgets as their
accessible `label`/`description` — this is a real, user-facing attribute
(what a screen reader announces), not decoration:

| Upstream site | Widget | a11y text |
|---|---|---|
| `src/gtk/window.blp:128` | elapsed-time label | "Elapsed time" |
| `src/gtk/window.blp:142` | remaining-time label | "Remaining time" |
| `src/gtk/playlist-view.blp:66-67` | search entry | "Search" / "Type to search songs" |
| `src/gtk/queue-row.blp:27` | cover placeholder | "No cover available" |
| `src/gtk/queue-row.blp:81` | queue row | "Currently playing" |
| `src/gtk/playback-control.blp:28,44,59,86,97,123,141` | skip-back/toggle-play/skip-forward/toggle-playlist/shuffle/repeat/menu buttons | 7 more |

None of these 8 widgets carry an `accessible_role`/accessible-label/
accessible-description call in the corresponding port files
(`lib/amberol/window.rb`, `lib/amberol/playlist_view.rb`,
`lib/amberol/queue_row.rb`, `lib/amberol/playback_control.rb`). The only
`accessible_role` calls anywhere in `lib/` are three unrelated ones
(`cover_picture.rb:32`, `marquee.rb:34`, `waveform_view.rb:43`), none of which
are these 8. Confirmed by grep: `grep -rn 'a11y\|accessible' lib/amberol/*.rb`
returns only those three lines; `grep -rn '"a11y"' lib/ exe/` returns nothing.

This is recorded here as a component-identification finding (the component is
the accessible name, not just the visible label) and carried into
`component-parity.md` and `translation-parity.md` as the same underlying gap.

## Still-open items from the prior survey, re-verified true today

- No XDG background portal request (`lib/amberol/application.rb:105-106`
  comments it as known-missing; `app.background-play` only holds/releases the
  app, it never calls the portal).
- No `PULSE_PROP_*` set on startup (upstream's `main.rs` sets the PulseAudio
  media role/app name; no equivalent in `lib/amberol.rb` or `exe/amberol`).
- Settings are a JSON file under `XDG_CONFIG_HOME`
  (`lib/amberol/settings.rb:10-56`), not a compiled GSettings schema — no
  `data/*.gschema.xml` ships, so nothing outside the app (dconf-editor, other
  processes) can read or set these keys.

These three are unchanged from the previous round's "Remaining work" and are
re-confirmed here by reading the current files, not copied forward.
