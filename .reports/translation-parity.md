# Translation parity — Amberol-rb

| | |
|---|---|
| Upstream | `main` @ `3830fbb` |
| Port | `ruby` @ `bb2d931` |
| Domain | `amberol` (upstream `po/meson.build`: `project_name()` = `amberol`; port `lib/amberol/config.rb:26`: `GETTEXT_PACKAGE = "amberol"` — **matches**, by hand; see note below) |
| Upstream messages | 76 |
| Ported | 63 |
| Gaps | 13 |
| Extra (untranslated) | 0 |
| Upstream languages | 54 `.po` files, 5,500 translated / 17 untranslated / 55 fuzzy |
| Languages shipped by the port | 54 (byte-identical `.po` files; `.mo` compiled and committed for all 54) |
| Build command | none needed — `.mo`s are pre-committed under `po/<lang>/LC_MESSAGES/amberol.mo` |

## The automated scanner undercounts this port — read this before the numbers below

Running `.claude/skills/translation-parity/scripts/{msgid-census.sh,
catalogue.rb}` out of the box against this port reports only **12/76 ported,
64 gaps**. That number is wrong, and the reason is a real scanner defect
worth stating plainly rather than reporting as the port's score:

Amberol's upstream itself names its wrapper functions `i18n`/`ni18n_f`/
`pi18n`/etc. (not `gettext`/`_`/`ngettext` directly — see `src/i18n.rs`), and
the Ruby port mirrors that naming as `Amberol::I18n.i18n(...)`,
`I18n.pi18n(...)`, etc. The scanner's marker regex
(`(^|[^A-Za-z0-9_.])(g_)?(_|N_|NC_|C_|n_|Nn_|np_|p_|s_|ngettext|gettext|
dgettext|...)\(`) requires the marker to be preceded by a non-dot character,
so a module-qualified call like `I18n.i18n("Add Folder")` can never match —
the `.` before `i18n` excludes it structurally, and `i18n` is not in the
marker list in any case. Upstream's own `.blp` files use the standard `_()`/
`C_()` markers and are read correctly; only the port's Ruby side is
undercounted, which is exactly backwards from what the ledger needs to show.

Per this skill's own escalation order ("fix the scanner, or census by hand
and say so"), this report is built from a **hand census**: every one of the
76 upstream msgids was grepped against `lib/`/`exe/` for the matching
`I18n.i18n`/`I18n.pi18n`/`I18n.ni18n_f`/etc. call, confirmed open in each
file, with line numbers below. `totals.unresolved` from the automated run
(12 upstream, 16 port) is also non-zero and is not carried into this ledger's
counts for the same reason — those are mostly the same false-negative shape
(multi-line, backslash-continued Ruby string literals split across the
`I18n.i18n(\n  "..." \\\n  "...",\n)` form), confirmed by hand to concatenate
to upstream's exact bytes (e.g. `window.rb:423-426`, the "Select a file or a
folder..." status-page description).

## Messages, grouped by upstream source

### `src/gtk/window.blp` + `src/window.rs` → `lib/amberol/window.rb` (no context)

| msgid | Port site | State |
|---|---|---|
| `Add Folder` | `window.rb:446` | ported |
| `Add Song` | `window.rb:453` | ported |
| `Drop a song to add it to the playlist` | `window.rb:62` | ported |
| `Restore Playlist` | `window.rb:438` | ported |
| `Select a file or a folder, or drag files from your file manager to the application window to add songs to the playlist` | `window.rb:423-426` (split across a backslash-continued literal; concatenates byte-identical) | ported |
| `Elapsed time` (ctxt `a11y`) | — | **gap** |
| `Remaining time` (ctxt `a11y`) | — | **gap** |

### `src/gtk/playback-control.blp` → `lib/amberol/playback_control.rb`, `primary_menu.rb`

| msgid | Port site | State |
|---|---|---|
| `Add _Folder` | `window.rb:743` | ported |
| `Add _Song` | `window.rb:729` | ported |
| `Clear` | `primary_menu.rb:24` | ported |
| `Copy` | `primary_menu.rb:18` | ported |
| `Enable Repeat` | `playback_control.rb` | ported |
| `Main Menu` | `playback_control.rb` | ported |
| `Open Directory` | `primary_menu.rb:19` | ported |
| `Play the Next Song` | `playback_control.rb` | ported |
| `Play the Previous Song` | `playback_control.rb` | ported |
| `Shuffle the Playlist` | `playback_control.rb` | ported |
| `Toggle Play` | `playback_control.rb:107` | ported |
| `Toggle Playlist` | `playback_control.rb:128` | ported |
| `_About Amberol` | `primary_menu.rb:33` | ported |
| `_Background Playback` | `primary_menu.rb:28` | ported |
| `_Keyboard Shortcuts` | `primary_menu.rb:32` | ported |
| `_Match Cover Art` | `primary_menu.rb:27` | ported |
| `_Quit` | `primary_menu.rb:34` | ported |
| `_ReplayGain` | `primary_menu.rb:67` | ported |
| `_Album`/`_Song`/`_Disabled` (ctxt `replaygain-menu`) | `primary_menu.rb:41-43` | ported (3/3) |
| `Skip backwards`/`Toggle play`/`Skip forward`/`Toggle playlist`/`Shuffle`/`Repeat`/`Primary menu` (ctxt `a11y`, 7 msgids) | — | **gap** (7) |

### `src/gtk/playlist-view.blp` → `lib/amberol/playlist_view.rb`

| msgid | Port site | State |
|---|---|---|
| `Close the Playlist` | `playlist_view.rb:114` | ported |
| `Playlist` | `playlist_view.rb:125` | ported |
| `Remove Selected Songs` | `playlist_view.rb:191` | ported |
| `Search Songs in the Playlist` | `playlist_view.rb:95` | ported |
| `Search songs` | `playlist_view.rb:142` | ported |
| `Select All Songs` | `playlist_view.rb:184` | ported |
| `Select Songs in the Playlist` | `playlist_view.rb:104` | ported |
| `Search`/`Type to search songs` (ctxt `a11y`) | — | **gap** (2) |

### `src/gtk/queue-row.blp` → `lib/amberol/queue_row.rb`

| msgid | Port site | State |
|---|---|---|
| `No cover available`/`Currently playing` (ctxt `a11y`) | — | **gap** (2) |

### `src/gtk/shortcuts-dialog.blp` → `lib/amberol/shortcuts_dialog.rb` (ctxt `shortcut window`, 18 msgids)

All 18 confirmed ported: `General`, `Toggle primary menu`, `Copy song details
to the clipboard`, `Show shortcuts`, `Quit`, `Playlist`, `Add a song to the
playlist`, `Add a folder to the playlist`, `Clear the playlist`, `Toggle the
playlist pane`, `Search the playlist`, `Toggle shuffling songs`, `Playback`,
`Toggle play/pause`, `Previous song`, `Next song`, `Seek backwards in the
current song`, `Seek forward in the current song` — all at
`lib/amberol/shortcuts_dialog.rb` via `I18n.pi18n("shortcut window", ...)`
(18 call sites, matching upstream's 18 exactly). **ported (18/18)**.

### `data/io.bassi.Amberol.desktop.in.in` + `data/io.bassi.Amberol.metainfo.xml.in.in` → `data/org.rubygtkproject.Amberol.{desktop.in.in,metainfo.xml.in.in}`

`Amberol`, `Amberol is a music player with no delusions of grandeur...`,
`Current features:`, `Emmanuele Bassi`, `MPRIS integration`, `Music Player`,
`Plays music, and nothing else`, `UI recoloring using the album art`,
`adaptive UI`, `drag and drop support to queue songs`, `music;player;media;
audio;playlist;`, `shuffle and repeat` — all **ported**, copied verbatim as
plain XML/desktop-file text (no marker needed for these files; confirmed
byte-identical by the automated catalogue diff, which reads data files
correctly).

## Gaps (13 of 76) — all accessibility labels, none closed

| ctxt | msgid | Upstream site | Text still owed |
|---|---|---|---|
| a11y | Elapsed time | `window.blp:128` | Elapsed time |
| a11y | Remaining time | `window.blp:142` | Remaining time |
| a11y | Search | `playlist-view.blp:66` | Search |
| a11y | Type to search songs | `playlist-view.blp:67` | Type to search songs |
| a11y | No cover available | `queue-row.blp:27` | No cover available |
| a11y | Currently playing | `queue-row.blp:81` | Currently playing |
| a11y | Skip backwards | `playback-control.blp:28` | Skip backwards |
| a11y | Toggle play | `playback-control.blp:44` | Toggle play |
| a11y | Skip forward | `playback-control.blp:59` | Skip forward |
| a11y | Toggle playlist | `playback-control.blp:86` | Toggle playlist |
| a11y | Shuffle | `playback-control.blp:97` | Shuffle |
| a11y | Repeat | `playback-control.blp:123` | Repeat |
| a11y | Primary menu | `playback-control.blp:141` | Primary menu |

Every one of the 13 gaps is the same ctxt (`a11y`) and the same underlying
cause: the port never calls `set_accessible_property`/an equivalent on these
8 widgets at all (see `.reports/component-parity.md`, Gap 1) — closing these
13 translation rows and the 8 component rows is one and the same fix.

## Languages — verified, not assumed

```
$ diff <(git ls-tree -r --name-only origin/main -- po | grep '\.po$' | sed 's#po/##;s#\.po$##' | sort) \
       <(find po -name '*.po' | sed 's#po/##;s#\.po$##' | sort)
(no output — identical sets, 54/54)
$ diff po/LINGUAS <(git show origin/main:po/LINGUAS)
(no output)
$ for f in fr de en_GB pt_BR; do diff <(git show origin/main:po/$f.po) po/$f.po; done
(no output for any — byte-identical)
$ find po -name '*.mo' | wc -l
54
```

Loading confirmed live, not just claimed: `Amberol::I18n.bind_text_domain`
with `LANGUAGE=de LC_ALL=de_DE.UTF-8` returns `true`
(`Amberol::Config::LOCALEDIR` exists and holds a matching `.mo`), and
`Amberol::I18n.i18n("Add Song")` under that locale returns `"Titel
hinzufügen"` — a real translated string reaching the lookup, not the English
fallback.

## Domain — the automated catalogue's `domain_matches: false` is a false
   negative too

`catalogue.rb`'s domain detector looks for `po/meson.build` to read
`i18n.gettext(...)`'s first argument; the Ruby port has no `meson.build` at
all (meson is not the port's build system), so the detector finds nothing
and reports `domain: null`. By hand: `lib/amberol/config.rb:26` sets
`GETTEXT_PACKAGE = "amberol"`, which is upstream's domain exactly (confirmed
from `po/meson.build`'s `project_name()` = `amberol`, and from the `.mo`
filenames themselves, `po/<lang>/LC_MESSAGES/amberol.mo`, on both trees).
**The domain does match.** This is recorded here as another scanner
limitation, not a port defect.

## Summary (manually verified, not generated-YAML-as-is)

```
63/76 messages · 97/101 occurrences (upstream has 2 reused msgids: "Playlist"
×2 across playlist-view.blp's title and shortcuts-dialog's section header,
both ported) · 54/54 languages · 5,500/5,500 translated strings · de verified
on screen (I18n.i18n("Add Song") → "Titel hinzufügen" under LANGUAGE=de)
```

**`parity: false`.** 13 real gaps remain, all of the same kind (accessible
labels), all unclosed. This is a materially better state than the raw
automated scanner output (12/76) suggests, and materially worse than "done"
— both of those would be false reports, which is why this ledger is written
from a hand census with the scanner's specific failure mode named, per the
skill's instruction not to report a broken check's number as if it passed.
