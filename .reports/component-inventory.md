# Amberol — component inventory

Surveyed against `origin/main` (upstream Rust/Blueprint, gtk-rs) vs. `ruby`
(this fork's `lib/`). Built with `.claude/skills/component-identification`'s
`component-scan.sh` run over a `git archive origin/main` checkout and over
`lib/`, cross-checked against the `.blp` templates and `data/*.gschema.xml`.

Upstream totals: 342 scan rows across 25 source/blueprint files (24 widget
types, 23 CSS classes, 31 signals, 27 distinct actions). Port (`ruby` branch)
totals: 201 scan rows across 20 `lib/` files. The gap is mostly shape (one
upstream component is often split .rs/.blp, one `lib/*.rb` file), not missing
coverage — see per-file notes below. **Every upstream user-facing unit this
survey found already has a corresponding `lib/*.rb` file on `ruby`.** No new
component files are needed; remaining work (if any) is filling gaps inside
existing files, which is `component-parity`'s job, not this inventory's.

## Application shell

| Upstream | Port (`lib/amberol/...`) | Kind | Present |
|---|---|---|---|
| `src/application.rs` | `application.rb` | Adw.Application subclass — actions (`app.quit`, `queue.*`, `win.*`), `Adw.AboutDialog` | yes |
| `src/application.rs` (About dialog portion) | `about_dialog.rb` | `Adw.AboutDialog` builder, split out of application.rb in the port | yes |
| `src/main.rs` | `rb.rb` / `amberol.rb` (entry point) | app bootstrap | yes |
| `src/window.rs` + `src/gtk/window.blp` | `window.rb` | `Adw.ApplicationWindow` template: `Adw.OverlaySplitView`, `Adw.ToastOverlay`, `Adw.Breakpoint`, drop target, file dialogs, `win.*`/`queue.*` actions, toast notifications | yes |
| `src/gtk/playback-control.blp` + `src/playback_control.rs` | `playback_control.rb` | `$AmberolPlaybackControl` widget: transport buttons, volume control slot, playlist/menu buttons, `primary_menu` model | yes |
| (menu model inside playback-control.blp: `menu primary_menu { ... }`) | `primary_menu.rb` | `Gio::Menu`/`Gtk::PopoverMenu` model — About/Preferences/Shortcuts/Quit + replaygain submenu | yes |
| `src/gtk/shortcuts-dialog.blp` | `shortcuts_dialog.rb` | `Adw.ShortcutsDialog` — 3 sections, 15 shortcut items | yes |

## Playlist / queue

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `src/playlist_view.rs` + `src/gtk/playlist-view.blp` | `playlist_view.rb` | `$AmberolPlaylistView`: `Adw.HeaderBar`/`Adw.ToolbarView`, `Gtk.ListView`, search bar+entry, action bar, progress bar, select/toggle/search actions | yes |
| `src/queue_row.rs` + `src/gtk/queue-row.blp` | `queue_row.rb` | one playlist row: check button, cover stack, title/artist/duration inscriptions, `card`/`selection-mode`/`song-title` etc. CSS, `active-notify` | yes |
| `src/audio/queue.rs` | `audio/queue.rb` | queue model (non-widget) | yes |
| `src/audio/shuffle.rs` | `audio/shuffle_list_model.rb` | `Gio::ListModel` shuffle wrapper, `items-changed` | yes |
| `src/sort.rs` | `sort.rb` | `Gtk.Sorter` subclass | yes |
| `src/search.rs` | `search.rb` | `Gtk.Filter` subclass | yes |

## Now-playing / song display

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `src/song_cover.rs` + `src/gtk/song-cover.blp` | `song_cover.rb` | cover art stack (image/placeholder `Gtk.StackPage`s), `card`/`dim-label` CSS | yes |
| `src/song_details.rs` + `src/gtk/song-details.blp` | `song_details.rb` | title/artist/album box, `song-title`/`song-artist`/`song-album` CSS | yes |
| `src/cover_picture.rs` | `cover_picture.rb` | custom `Gtk.Widget` subclass painting the cover (`cover` CSS, css-name `picture`) | yes |
| `src/marquee.rs` | `marquee.rb` | scrolling-label widget (css-name `label`), `Adw.TimedAnimation`-driven, `done` signal | yes |
| `src/waveform_view.rs` | `waveform_view.rb` | waveform widget: drag gesture, key/motion controllers, `Adw.StyleManager` theming (css-name `waveformview`) | yes |
| `src/audio/waveform_generator.rs` | `audio/waveform_generator.rb` | waveform data generation (non-widget) | yes |
| `src/drag_overlay.rs` | `drag_overlay.rb` | `Adw.Bin`/`Adw.StatusPage` drop overlay, `Gtk.DropTarget` ×4, `blurred`/`drag-overlay-status-page` CSS | yes |

## Volume / transport

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `src/volume_control.rs` + `src/gtk/volume-control.blp` | `volume_control.rb` | mute button + `Gtk.Scale`, scroll controller, `volume.toggle-mute` action | yes |

## Audio backend (non-widget, behind the UI)

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `src/audio/mod.rs` | `audio.rb` | module aggregator | yes |
| `src/audio/controller.rs` | `audio/controller.rb` | playback coordinator | yes |
| `src/audio/player.rs` | `audio/player.rb` | player facade | yes |
| `src/audio/state.rs` | `audio/player_state.rb` | playback state enum/struct | yes |
| `src/audio/gst_backend.rs` | `audio/gst_backend.rb` | GStreamer backend — drives `GstPlay::Play` from the `gstreamer_play` gem | yes |
| `src/audio/cover_cache.rs` | `audio/cover_cache.rb` | cover art cache | yes |
| `src/audio/song.rs` | `audio/song.rb` | song/tag model | yes |
| (tag reading, split out of song.rs upstream) | `audio/tag_reader.rb` | tag extraction | yes |
| `src/audio/inhibit_controller.rs` | `audio/inhibit_controller.rb` | `Gtk.Application` idle/suspend inhibitor | yes |
| `src/audio/mpris_controller.rs` | `audio/mpris_controller.rb` | MPRIS D-Bus controller (`play`/`pause`/`next`/`previous`/`seek`/`raise`/`stop`/`set-loop-status` signals) | yes |

## Support / data

| Upstream | Port | Kind | Present |
|---|---|---|---|
| `src/config.rs.in` | `config.rb` | build-time constants (app id, version) | yes |
| `src/i18n.rs` | `i18n.rb` | gettext setup | yes |
| `src/utils.rs` | `utils.rb` | misc helpers | yes |
| `src/gtk/style.css` | `style.rb` | CSS provider loader | yes |
| `data/io.bassi.Amberol.gschema.xml` (5 keys: `window-width`, `window-height`, `enable-recoloring`, `replay-gain`, `background-play`) | `settings.rb` | settings store — all 5 keys present with matching defaults and the `replay-gain` enum nicks (`album`/`track`/`off`); backed by a JSON file under `XDG_CONFIG_HOME` instead of compiled GSettings schema (documented in-file) | yes |
| `src/amberol.gresource.xml`, `data/icons/**`, `src/assets/icons/**` | — | GResource/icon manifest — not a widget component; out of this inventory's scope (asset packaging, not `lib/` code) | n/a |
| `data/io.bassi.Amberol.metainfo.xml.in.in`, `.desktop.in.in`, `.service.in` | — | app metadata / D-Bus activation — packaging, not a `lib/` widget component | n/a |
| `po/*.po` (62 locales) | `po/*.po` (same 62 `.po` files present in this fork, mirrored from upstream) | translation catalogue | present (translation-parity scope, not re-verified here) |

## Gem wiring check (per task instructions)

- `gstreamer_play` (`GstPlay`): `require`d in `lib/amberol/audio/gst_backend.rb` and
  driven directly (`GstPlay::Play.new`, `GstPlay::PlayMessage` dispatch for
  errors/warnings/EOS/position/seek/volume) — matches the live playback path,
  consistent with the most recent commit on this branch
  ("Drive playback through GstPlay::Play for real instead of stubbing it
  out"). Declared in `amberol-rb.gemspec` (`~> 1.1`) and `nix/Gemfile`.
  **Not regressed.**
- No dependency is declared in the gemspec without a corresponding `require`
  under `lib/` (checked `gtk4`, `adwaita`, `glib2`, `gstreamer_play`,
  `gstreamer`, `gettext`).

## Conclusion

Every upstream user-facing unit (window, dialogs, playlist/queue views, rows,
playback/volume controls, cover/song-detail/waveform widgets, menus,
shortcuts window, settings) already has a corresponding `lib/amberol/*.rb`
file on `ruby`. This survey found **no missing component files** to scaffold.
Verifying that each existing file's widget tree, CSS classes, signals and
actions fully match upstream (not just that the file exists) is
`component-parity` work, out of scope for this identification pass.
