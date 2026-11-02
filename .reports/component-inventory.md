# Amberol — upstream component inventory

Survey of `origin/main` (Rust + blueprint) against `lib/` on the `ruby` branch,
produced with the `component-identification` skill. One section per component,
in the order a user meets it. No app code was written in this step.

Upstream is gtk-rs with blueprint: **a component is a pair of files** — the
`src/*.rs` subclass (properties, actions, signal handlers) and the matching
`src/gtk/*.blp` (widget tree, CSS classes, action names). Both halves are
unioned into one `lib/amberol/*.rb` in the port.

Target naming follows the one file already on `ruby`
(`lib/amberol/application.rb`): `lib/amberol/<thing>.rb`, and
`lib/amberol/audio/<thing>.rb` mirroring upstream's `src/audio/`.

## Totals

| | Upstream | `ruby` branch |
|---|---:|---:|
| Source files contributing UI | 21 (`src/*.rs`) + 8 `.blp` | 1 |
| Distinct component units | 24 | 1 (placeholder) |
| GAction names | 19 | 0 |
| Accelerators | 13 | 0 |
| CSS classes in `src/gtk/style.css` | 15 app-defined + 5 custom CSS names | 0 |
| GSettings keys | 5 | 0 |
| Translated catalogues (`po/`) | 54 languages | 0 |

Everything below is a gap except `application.rb`, which exists as a
window-plus-`Adwaita::StatusPage` placeholder and is **not** the upstream
application class.

---

## 1. `src/application.rs` → `lib/amberol/application.rb` — the application object

Kind: **application**. Status: **partial** (placeholder only).

| Element | Detail |
|---|---|
| Base | `adw::Application`, app id `io.bassi.Amberol`, flags `HANDLES_OPEN`, resource base `/io/bassi/Amberol` |
| Actions | `app.quit`, `app.about`, `app.background-play` (stateful boolean, backed by GSettings), `app.shortcuts` (referenced by the menu and the shortcuts dialog) |
| Accelerators | `app.quit` `<primary>q`; `queue.add-song` `<primary>s`; `queue.add-folder` `<primary>a`; `queue.clear` `<primary>L`; `queue.toggle` `F9`; `queue.search` `<primary>F`; `queue.shuffle` `<primary>r`; `win.seek-backwards` `<primary>Left`; `win.seek-forward` `<primary>Right`; `win.previous` `<primary>b`; `win.next` `<primary>n`; `win.play` `<primary>p`; `win.copy` `<primary>c` |
| Behaviour | `activate` presents the single window; `open` forwards files to `Window#open_files`; `startup` sets the default icon name; owns the `AudioPlayer`; watches GSettings `background-play` and takes/drops an application hold; requests the XDG background portal |

Port note: `Adwaita::Application` is broken in the Ruby bindings — the existing
file correctly uses `Gtk::Application`. The port has no portal binding
available; that is a gap to record, not a decision.

### 1a. `src/application.rs` (`show_about`) → `lib/amberol/about_dialog.rb` — About

Kind: **dialog**. Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Adw.AboutDialog` | 1 | — | fired by `app.about` | icon = app id, name "Amberol", developer "Emmanuele Bassi", version, copyright "© 2022 Emmanuele Bassi", website `https://apps.gnome.org/Amberol/`, issue URL, GPL-3.0, `translator_credits` from the `translator-credits` msgid |

---

## 2. `src/window.rs` + `src/gtk/window.blp` → `lib/amberol/window.rb` — the main window

Kind: **window**. Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (`AmberolWindow`) | 1 | `devel` (only when app id ends `Devel`) | `close-request` → saves `window-width`/`window-height`, unbinds queue/state/waveform | `handle-menubar-accel`, width-request 360, height-request 660, default-width 800 |
| `Gtk.WindowHandle` | 1 | — | — | root child |
| `$DragOverlay` | 1 | — | hosts the drop target | title _("Drop a song to add it to the playlist") |
| `Adw.ToastOverlay` | 1 | — | `add_toast`, `add_skip_to_toast` | see Toasts below |
| `Gtk.Stack` `main_stack` | 1 | `main-window` (added/removed dynamically by `update_style`) | — | crossfade; pages `initial-view`, `main-view` |
| `Adw.ToolbarView` | 2 | — | — | one per stack page |
| `Adw.HeaderBar` | 2 | — | — | `show-title: false` both |
| `Adw.Breakpoint` | 1 | — | `max-width: 560sp` → `split_view.collapsed: true` | |
| `Adw.OverlaySplitView` `split_view` | 1 | — | `notify::collapsed`, `notify::show-sidebar` | max-sidebar-width 330, sidebar-width-fraction 0.4 |
| `Gtk.Box` `main_box` | 1 | `main-box` | — | vertical, spacing 6 |
| `Gtk.CenterBox` | 1 | — | — | holds the two time labels |
| `Gtk.Label` `elapsed_label` | 1 | `caption`, `numeric` | — | a11y "Elapsed time", default "0:00" |
| `Gtk.Label` `remaining_label` | 1 | `caption`, `numeric` | — | a11y "Remaining time", default "0:00" |
| `Gtk.CssProvider` | 1 | — | — | per-display provider at priority 400; `update_style` writes `--background-color-0..4` from the cover palette |
| `Gtk.DropTarget` (controller) | 1 | — | `drop` | name `file-drop-target`, `COPY`, `GdkFileList` |

Window actions installed here:

| Action | Kind | Does |
|---|---|---|
| `win.play` | plain | `player.toggle_play` |
| `win.previous` / `win.next` | plain | skip |
| `win.seek-backwards` / `win.seek-forward` | plain | seek |
| `win.copy` | plain | clipboard text _("Currently playing “{title}” by “{artist}”") |
| `win.open-directory` | async | `Gtk.FileLauncher.open_containing_folder`, falls back to a toast _("Unable to open folder") |
| `win.skip-to` | plain, `u` param | skip to index and play (toast button target) |
| `win.enable-recoloring` | stateful boolean | GSettings `enable-recoloring` |
| `win.replaygain` | property action → `replaygain-mode` enum | `album` / `track` / `off` |
| `queue.repeat-mode` | plain | cycles repeat mode |
| `queue.add-song` | async | see dialog 2a |
| `queue.add-folder` | async | see dialog 2b |
| `queue.clear` | plain | clears the queue |
| `queue.restore-playlist` | plain | reloads the cached playlist |
| `queue.toggle` | property action → `playlist-visible` | |
| `queue.shuffle` | property action → `playlist-shuffled` | |
| `queue.select` | property action → `playlist-selection` | |
| `queue.search` | property action → `playlist-search` | |

Window properties: `playlist-shuffled`, `playlist-visible`, `playlist-selection`,
`playlist-search`, `replaygain-mode`.

Sensitivity rules (`set_initial_state`, `bind_queue`): `win.play` and
`win.previous` need a non-empty queue; `win.next` needs more than one song or a
non-consecutive repeat mode; `queue.toggle` needs a non-empty queue;
`queue.shuffle` needs more than one song; `win.replaygain` needs ReplayGain
support in the GStreamer backend; `win.enable-recoloring` needs a cover palette;
`queue.add-song` / `queue.add-folder` / `queue.clear` are disabled while a
playlist loads.

### 2a. `queue.add-song` → part of `lib/amberol/window.rb` — Add Song file dialog

Kind: **dialog**. Status: **missing**.

`Gtk.FileDialog`, accept label _("_Add Song"), title _("Open File"), modal,
initial folder XDG Music (else cwd), one `Gtk.FileFilter` named _("Audio files")
with mime `audio/*`, `open_multiple`. Empty result → toast _("Unable to access
files").

### 2b. `queue.add-folder` → part of `lib/amberol/window.rb` — Add Folder dialog

Kind: **dialog**. Status: **missing**.

`Gtk.FileDialog`, accept label _("_Add Folder"), title _("Open Folder"), modal,
initial folder XDG Music, `select_multiple_folders`. Empty result → the same
toast.

### 2c. Empty state — `status_page` in `window.blp`

Kind: **empty state**. Status: **placeholder exists, wrong content**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Adw.Clamp` | 1 | — | — | maximum-size 450, vexpand, valign fill |
| `Adw.StatusPage` `status_page` | 1 | — | — | title "Amberol" (untranslated), description _("Select a file or a folder, or drag files from your file manager to the application window to add songs to the playlist"), icon set at runtime to the app id |
| `Gtk.Box` | 1 | — | — | vertical, halign center, homogeneous, spacing 12 |
| `Gtk.Button` `restore_playlist_button` | 1 | `pill`, plus `suggested-action` **only when a cached playlist exists** | `queue.restore-playlist` | hidden when there is no cached playlist |
| `Gtk.Button` `add_folder_button` | 1 | `pill`, plus `suggested-action` when there is **no** cached playlist | `queue.add-folder` | becomes the window's default widget in the initial view |
| `Gtk.Button` | 1 | `pill` | `queue.add-song` | label _("Add Song") |

### 2d. Toasts — `toast_overlay`

Kind: **error/notice states**. Status: **missing**. All go through
`Adw.ToastOverlay`; the strings are the inventory:

- _("No available song found") — restoring an empty cached playlist
- _("No songs found") — nothing loadable in the selection
- _("Unable to access files") — empty file-dialog result or empty `open` list
- _("Unable to access dropped files") — empty drop
- _("Unable to open folder") — `win.open-directory` failure
- _("Added a new song") with button _("Play") → `win.skip-to` with the index
- _("Added one song") / _("Added {} songs") — plural form

---

## 3. `src/playback_control.rs` + `src/gtk/playback-control.blp` → `lib/amberol/playback_control.rb`

Kind: **widget** (custom CSS name `playbackcontrol`, `BinLayout`, a11y role
Group). Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Box` `center_box` | 1 | — | — | vertical, spacing 6, width-request 256 |
| `Gtk.Box` `controls_box` | 1 | — | — | spacing 24, halign center |
| `Gtk.Button` `previous_button` | 1 | `circular` | `win.previous` | tooltip _("Play the Previous Song"), a11y "Skip backwards" |
| `Gtk.Button` `play_button` | 1 | `circular`, `large` | `win.play` | icon toggles `media-playback-start-symbolic` ↔ `media-playback-pause-symbolic`; tooltip _("Toggle Play"); window default widget in main view |
| `Gtk.Button` `next_button` | 1 | `circular` | `win.next` | tooltip _("Play the Next Song") |
| `$AmberolVolumeControl` | 1 | — | — | hexpand |
| `Gtk.CenterBox` | 1 | — | — | bottom row |
| `Gtk.Box` `start_box` | 1 | — | — | spacing 12, margin-end 18 |
| `Gtk.ToggleButton` `playlist_button` | 1 | `circular` | `queue.toggle` | icon `view-queue-symbolic`, tooltip _("Toggle Playlist") |
| `Gtk.ToggleButton` `shuffle_button` | 1 | `circular` | `queue.shuffle` | tooltip _("Shuffle the Playlist") |
| `Gtk.Box` `end_box` | 1 | — | — | spacing 12, margin-start 18 |
| `Gtk.Button` `repeat_button` | 1 | `circular` | `queue.repeat-mode` | icon + tooltip set from repeat mode: `media-playlist-consecutive-symbolic` _("Do Not Repeat"), `media-playlist-repeat-symbolic` _("Repeat All Songs"), `media-playlist-repeat-song-symbolic` _("Repeat the Current Song") |
| `Gtk.MenuButton` `menu_button` | 1 | `circular` | model `primary_menu` | primary, direction up, tooltip _("Main Menu") |

### 3a. `menu primary_menu` in `playback-control.blp` → `lib/amberol/primary_menu.rb`

Kind: **menu**. Status: **missing**. Five sections, 13 items:

| Section | Items (label → action) |
|---|---|
| 1 | _("Copy") → `win.copy`; _("Open Directory") → `win.open-directory` |
| 2 | _("Add _Song") → `queue.add-song`; _("Add _Folder") → `queue.add-folder`; _("Clear") → `queue.clear` |
| 3 | _("_Match Cover Art") → `win.enable-recoloring`; _("_Background Playback") → `app.background-play` |
| 4 | submenu _("_ReplayGain") with _("_Album") / _("_Song") / _("_Disabled") → `win.replaygain` targets `album`, `track`, `off` |
| 5 | _("_Keyboard Shortcuts") → `app.shortcuts`; _("_About Amberol") → `app.about`; _("_Quit") → `app.quit` |

---

## 4. `src/volume_control.rs` + `src/gtk/volume-control.blp` → `lib/amberol/volume_control.rb`

Kind: **widget** (CSS name `volume`, `BoxLayout`, a11y Group). Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Button` `volume_low_button` | 1 | `flat`, `circular` | `volume.toggle-mute` | icon flips `audio-volume-low-symbolic` ↔ `audio-volume-muted-symbolic` at zero |
| `Gtk.Scale` `volume_scale` | 1 | — | adjustment `notify::value` → `notify volume` + emit `volume-changed` | hexpand, margin-end 6; adjustment 0..1 step 0.05 value 1 |
| `Gtk.Image` `volume_high_image` | 1 | — | — | `audio-volume-high-symbolic`, margin-end 10 |
| `Gtk.EventControllerScroll` (controller) | 1 | — | `scroll` | name `volume-scroll`, VERTICAL, adjusts by one step and stops propagation |

Properties `volume` (double 0..1, default 1), `toggle-mute` (boolean, backs the
property action). Custom signal `volume-changed(double)`, consumed by the window
to drive `player.set_volume`. Stylesheet rules target `volume > scale trough
highlight` / `slider` and `volume:hover > scale`.

---

## 5. `src/playlist_view.rs` + `src/gtk/playlist-view.blp` → `lib/amberol/playlist_view.rb`

Kind: **page** (sidebar of the split view; CSS name `playlistview`, `BinLayout`,
a11y Group). Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Adw.ToolbarView` | 1 | `playlist-background` | — | |
| `Adw.HeaderBar` | 1 | — | — | |
| `Gtk.ToggleButton` `search_button` | 1 | — | `queue.search` | `system-search-symbolic`, tooltip _("Search Songs in the Playlist") |
| `Gtk.Box` `queue_length_box` | 1 | — | — | title widget, vertical |
| `Gtk.Label` | 1 | `heading` | — | _("Playlist") |
| `Gtk.Label` `queue_length_label` | 1 | `caption` | — | remaining time; hidden when no current song |
| `Gtk.Button` `back_button` | 1 | — | `queue.toggle` | `go-previous-symbolic`, visible only when the split view is collapsed, tooltip _("Close the Playlist") |
| `Gtk.ToggleButton` `select_button` | 1 | — | `queue.select` | `selection-mode-symbolic`, tooltip _("Select Songs in the Playlist") |
| `Gtk.SearchBar` `playlist_searchbar` | 1 | — | `notify::search-mode-enabled` → window `playlist-search` | key capture widget is the window; entry connected |
| `Gtk.SearchEntry` `playlist_searchentry` | 1 | — | `search-changed` → scroll list to top; `text` bound to the filter and the sorter | placeholder _("Search songs"), a11y label "Search" / description "Type to search songs" |
| `Gtk.Overlay` `playlist_overlay` | 1 | — | — | |
| `Gtk.ProgressBar` `playlist_progress` | 1 | `osd` | — | valign start, hidden; `begin_loading` / `update_loading` / `end_loading` |
| `Gtk.ScrolledWindow` | 1 | — | — | hscrollbar never, propagate-natural-height |
| `Gtk.ListView` `queue_view` | 1 | `navigation-sidebar` | `activate` → skip to song / toggle selection | single-click-activate; `SignalListItemFactory` set up in `window.rs` |
| `Gtk.ActionBar` `queue_actionbar` | 1 | `flat` | revealed with `playlist-selection` | |
| `Gtk.Button` `queue_select_all_button` | 1 | — | `clicked` → select every song (filtered set while searching) | `edit-select-all-symbolic`, tooltip _("Select All Songs") |
| `Gtk.Label` `queue_selected_label` | 1 | `caption` | — | _("No song selected") / _("{} song selected") / _("{} songs selected") |
| `Gtk.Button` `queue_remove_button` | 1 | — | `clicked` → remove selected songs, re-store playlist | `app-remove-symbolic`, tooltip _("Remove Selected Songs") |

Repeater: `queue_view` renders one `QueueRow` per song in the queue model, via a
`Gtk.FilterListModel` → `Gtk.SortListModel` → `Gtk.NoSelection` chain.

---

## 6. `src/queue_row.rs` + `src/gtk/queue-row.blp` → `lib/amberol/queue_row.rb`

Kind: **row** (CSS name `queuerow`, `BoxLayout`, a11y Group). Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Stack` `row_stack` | 1 | — | — | pages `song-details`, `selection-mode` |
| `Gtk.Box` | 2 | `song-details` | — | one per stack page |
| `Gtk.Stack` `song_cover_stack` | 1 | — | — | pages `no-cover`, `cover` |
| `Gtk.Image` | 1 | `dim-label`, `card`, `small` | — | `folder-music-symbolic`, 32px, a11y "No cover available" |
| `$AmberolCoverPicture` `song_cover_image` | 1 | `card` | — | cover-size `1` (Small) |
| `Gtk.Inscription` `song_title_label`, `selection_title_label` | 2 | `song-title` | — | xalign 0, ellipsize end |
| `Gtk.Inscription` `song_artist_label`, `selection_artist_label` | 2 | `song-artist` | — | xalign 0, ellipsize end |
| `Gtk.Image` `song_playing_image`, `selection_playing_image` | 2 | — | — | `audio-only-symbolic`, 16px, opacity 0/1 by `playing`; a11y "Currently playing" |
| `Gtk.CheckButton` `selected_button` | 1 | `selection-mode` | `notify::active` → sets `Song#selected`, notifies `selected` | |

Properties: `song`, `song-artist`, `song-title`, `song-cover`, `playing`,
`selection-mode`, `selected`. The stylesheet also defines
`queuerow .currently-playing` (padding, bold) — defined in `style.css` and not
applied anywhere in the current upstream tree; worth noting rather than porting
blindly.

---

## 7. `src/song_cover.rs` + `src/gtk/song-cover.blp` → `lib/amberol/song_cover.rb`

Kind: **widget** (CSS name `songcover`, `BinLayout`, a11y Group). Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Box` | 1 | — | — | halign/valign center |
| `Gtk.Stack` `cover_stack` | 1 | — | — | pages `no-image`, `cover-image`; switched by `show_cover_image` |
| `Gtk.Image` | 1 | `card`, `dim-label` | — | `folder-music-symbolic`, 64px, overflow hidden |
| `$AmberolCoverPicture` `album_image` | 1 | `cover` (from `CoverPicture`) | — | large size |

Stylesheet: `songcover picture.cover` / `image.card` get the three-layer box
shadow and 12px radius; `.main-window songcover picture.cover` gets the palette
gradient.

---

## 8. `src/song_details.rs` + `src/gtk/song-details.blp` → `lib/amberol/song_details.rb`

Kind: **widget** (CSS name `songdetails`, `BinLayout`, a11y Group). Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Box` | 2 | — | — | vertical, spacing 12 / margins 6 |
| `$AmberolMarquee` `song_title_label` | 1 | `song-title` | bound to `PlayerState:title` | width-chars 20 |
| `$AmberolMarquee` `song_artist_label` | 1 | `song-artist` | bound to `PlayerState:artist` | width-chars 25 |
| `$AmberolMarquee` `song_album_label` | 1 | `song-album` | bound to `PlayerState:album` | width-chars 25 |

---

## 9. `src/marquee.rs` → `lib/amberol/marquee.rb`

Kind: **widget** (CSS name `label`, a11y role Label). Status: **missing**.

A single child `Gtk.Label` that scrolls horizontally when the text does not fit,
driven by `Adw.TimedAnimation` + `Adw.CallbackAnimationTarget` with
`EaseInOutCubic` and a 1500 ms rest between passes. Properties `label`,
`width-chars`. No CSS classes of its own; the classes come from the caller
(`song-title`, `song-artist`, `song-album`).

Port note: this is a custom `snapshot`/`measure` widget. Expect a reduced Ruby
version (a `Gtk::Label` with ellipsizing, or a `Gtk::ScrolledWindow`-based
scroller); whatever is built, the shortfall is a gap, not a design choice.

---

## 10. `src/waveform_view.rs` → `lib/amberol/waveform_view.rb`

Kind: **widget** (CSS name `waveformview`, a11y role Slider). Status: **missing**.

Custom-drawn seek bar. Property `position` (double). Custom signal
`position-changed(double)`, consumed by the window to seek and play.
Controllers: `Gtk.GestureDrag` (`drag-begin`, `drag-update`),
`Gtk.EventControllerMotion` (`motion`, `leave` — hover cursor), and
`Gtk.EventControllerKey` (`key-released` — keyboard seeking); `can-focus: true`
in `window.blp`. Peaks come from `WaveformGenerator`; `notify::has-peaks`
re-pushes them. Stylesheet: `waveformview { padding-bottom: 6px }`.

---

## 11. `src/cover_picture.rs` → `lib/amberol/cover_picture.rb`

Kind: **widget** (CSS name `picture`, a11y role Img, a11y label _("Cover
image")). Status: **missing**.

Adds the `cover` CSS class to itself and sets `overflow: hidden`. Properties
`cover` (`Gdk.Texture`) and `cover-size` (enum `AmberolCoverSize`: `Large` 192px
/ `Small` 48px). Constant-size request mode; custom `snapshot` scales and
centres the texture with trilinear filtering; redraws on
`notify::scale-factor`.

---

## 12. `src/drag_overlay.rs` → `lib/amberol/drag_overlay.rb`

Kind: **widget / drop target host** (CSS name `dragoverlay`, extends `Adw.Bin`).
Status: **missing**.

| Widget | × | CSS | Signals/Actions | Notes |
|---|---:|---|---|---|
| `Gtk.Overlay` | 1 | — | — | hosts the real content |
| `Gtk.Revealer` | 1 | — | — | crossfade, `can-target: false` |
| `Adw.StatusPage` | 1 | `drag-overlay-status-page` | — | icon `folder-music-symbolic`, title from the `title` property |
| `Gtk.DropTarget` (controller) | 1 | — | `notify::current-drop` → reveal and add/remove `blurred` on the child | set by the window |

Properties `title`, `child`, `drop-target`. Stylesheet classes
`drag-overlay-status-page` (accent tint, 32px padding) and `blurred` (6px blur).

---

## 13. `src/gtk/shortcuts-dialog.blp` → `lib/amberol/shortcuts_dialog.rb`

Kind: **keyboard shortcuts dialog**. Status: **missing**. A standalone
blueprint with no backing Rust file; reached through `app.shortcuts`.

`Adw.ShortcutsDialog` with three `Adw.ShortcutsSection`s and 15
`Adw.ShortcutsItem`s:

| Section | Items |
|---|---|
| "General" | Toggle primary menu (`F10`); Copy song details to the clipboard (`win.copy`); Show shortcuts (`app.shortcuts`); Quit (`app.quit`) |
| "Playlist" | Add a song (`queue.add-song`); Add a folder (`queue.add-folder`); Clear the playlist (`queue.clear`); Toggle the playlist pane (`queue.toggle`); Search the playlist (`queue.search`); Toggle shuffling songs (`queue.shuffle`) |
| "Playback" | Toggle play/pause (`win.play`); Previous song (`win.previous`); Next song (`win.next`); Seek backwards (`win.seek-backwards`); Seek forward (`win.seek-forward`) |

All titles use the `shortcut window` gettext context.

---

## 14. `src/search.rs` → `lib/amberol/search.rb` — `FuzzyFilter`

Kind: **model/filter** (`Gtk.Filter` subclass). Status: **missing**. Property
`search`; fuzzy-matches a song's title, artist and album. Drives the playlist's
`Gtk.FilterListModel`.

## 15. `src/sort.rs` → `lib/amberol/sort.rb` — `FuzzySorter`

Kind: **model/sorter** (`Gtk.Sorter` subclass). Status: **missing**. Property
`search`; ranks by fuzzy match score. Drives the `Gtk.SortListModel`.

## 16. `src/utils.rs` → `lib/amberol/utils.rb`

Kind: **support**. Status: **missing**. `settings_manager`, `format_time`,
`format_remaining_time` (the `-0:00` form), cover texture loading and disk
caching, `load_palette` (the colours `update_style` turns into CSS variables),
nautilus-style filename comparison, recursive folder loading,
`store_playlist` / `load_cached_songs` / `has_cached_playlist`.

## 17. `src/i18n.rs` → `lib/amberol/i18n.rb`

Kind: **support**. Status: **missing**. `i18n`, `i18n_f`, `i18n_k`, `ni18n*`,
`pi18n*`, `pni18n*` — positional `{}` and keyword `{name}` substitution over
gettext. The port needs the keyword and plural forms because the window's
remaining-time and selected-count strings use them.

## 18. `src/config.rs.in` → `lib/amberol/config.rb`

Kind: **support**. Status: **missing**. `APPLICATION_ID`, `VERSION`,
`GETTEXT_PACKAGE`, `LOCALEDIR`, `PKGDATADIR`, `PROFILE`. `lib/amberol/rb/version.rb`
exists on `ruby` but is the gem version, not this.

## 19. `src/main.rs` → `exe/amberol` / `lib/amberol.rb`

Kind: **entry point**. Status: **partial** (`lib/amberol.rb` requires the
application; there is no locale, GStreamer or PulseAudio setup). Upstream sets
the locale and text domain, sets `PULSE_PROP_*` environment variables, loads the
GResource bundle, sets the application and program name, initialises GStreamer,
then runs the application.

---

## Audio model — `src/audio/` → `lib/amberol/audio/`

Not widgets, but every UI binding above reads from these, so they are part of
the port's component graph. All **missing**.

| Upstream | Target | Kind | Notes |
|---|---|---|---|
| `src/audio/mod.rs` | `lib/amberol/audio.rb` | module | the player/state/queue/backend/controllers layout |
| `src/audio/player.rs` | `lib/amberol/audio/player.rb` | model | `AudioPlayer`; enums `PlaybackAction`, `PlaybackState`, `RepeatMode`, `ReplayGainMode`, `SeekDirection`; play/pause/skip/seek/volume/replaygain |
| `src/audio/state.rs` | `lib/amberol/audio/player_state.rb` | model | read-only properties `playing`, `song`, `title`, `artist`, `album`, `duration`, `cover`, `position`, `volume` — the object the window binds to |
| `src/audio/queue.rs` | `lib/amberol/audio/queue.rb` | model | `Gio.ListModel`; properties `current`, `repeat-mode`, `n-songs`; add/remove/clear/skip/shuffle/selection |
| `src/audio/song.rs` | `lib/amberol/audio/song.rb` | model | `Song` + `SongData`; properties `uri`, `artist`, `title`, `album`, `duration`, `cover`, `playing`, `selected`; tag reading, cover palette |
| `src/audio/shuffle.rs` | `lib/amberol/audio/shuffle_list_model.rb` | model | shuffling `Gio.ListModel` wrapper with an anchor |
| `src/audio/gst_backend.rs` | `lib/amberol/audio/gst_backend.rb` | backend | GStreamer `playbin` wrapper, ReplayGain element, seek, volume |
| `src/audio/cover_cache.rs` | `lib/amberol/audio/cover_cache.rb` | support | global texture + palette cache |
| `src/audio/waveform_generator.rs` | `lib/amberol/audio/waveform_generator.rb` | model | property `has-peaks`; produces the peaks the waveform view draws |
| `src/audio/mpris_controller.rs` | `lib/amberol/audio/mpris_controller.rb` | integration | MPRIS2 — the desktop's media controls |
| `src/audio/inhibit_controller.rs` | `lib/amberol/audio/inhibit_controller.rb` | integration | suspend inhibitor, reason _("Playing music") |
| `src/audio/controller.rs` | `lib/amberol/audio/controller.rb` | interface | the `Controller` trait the three controllers implement |

---

## Data, resources and translations

| Upstream | Target | Status | Notes |
|---|---|---|---|
| `data/io.bassi.Amberol.gschema.xml` | `lib/amberol/settings.rb` + a schema under `data/` | missing | keys `window-width` (600), `window-height` (300), `enable-recoloring` (true), `replay-gain` (enum `album`/`track`/`off`, default `off`), `background-play` (true) |
| `src/gtk/style.css` | `lib/amberol/style.rb` (or a `data/style.css` loaded by a `Gtk::CssProvider`) | missing | 15 app classes/selectors: `main-box`, `main-window`, `song-title`, `song-artist`, `song-album`, `song-details`, `currently-playing`, `selection-mode`, `card.small`, `drag-overlay-status-page`, `blurred`, `playlist-background`, `button.large`, plus the custom CSS names `songcover`, `songdetails`, `waveformview`, `playbackcontrol`, `queuerow`, `dragoverlay`, `volume` |
| `src/amberol.gresource.xml` + `src/assets/icons/*.svg` | `data/icons/` registered with `Gtk::IconTheme#add_search_path` | missing | 17 bundled symbolic icons, including `app-remove`, `audio-only`, `edit-select-all`, `folder-music`, `selection-mode`, `view-queue`, `view-queue-rtl` and the five playback/repeat icons |
| `data/icons/hicolor/**` | `data/icons/` | missing | app icon, Devel variant, symbolic variants |
| `data/io.bassi.Amberol.desktop.in.in` | `data/*.desktop` | missing | also the only place `audio/*` MIME handling is declared |
| `data/io.bassi.Amberol.metainfo.xml.in.in` | `data/*.metainfo.xml` | missing | |
| `data/io.bassi.Amberol.service.in` | `data/*.service` | missing | D-Bus activation |
| `po/` (54 languages, `LINGUAS`, `POTFILES.in`) | `po/` | missing | `POTFILES.in` lists 5 blueprints and 5 Rust files as translatable; the port's equivalents are `window.rb`, `playback_control.rb`, `playlist_view.rb`, `queue_row.rb`, `shortcuts_dialog.rb`, `application.rb`, `cover_picture.rb`, `audio/song.rb`, `audio/inhibit_controller.rb` |

---

## Summary table

| # | Upstream file(s) | Target | Kind | Exists |
|---|---|---|---|---|
| 1 | `src/application.rs` | `lib/amberol/application.rb` | application | partial (placeholder) |
| 1a | `src/application.rs` (`show_about`) | `lib/amberol/about_dialog.rb` | dialog | no |
| 2 | `src/window.rs` + `src/gtk/window.blp` | `lib/amberol/window.rb` | window (+ 2 file dialogs, empty state, toasts) | no |
| 3 | `src/playback_control.rs` + `src/gtk/playback-control.blp` | `lib/amberol/playback_control.rb` | widget | no |
| 3a | `menu primary_menu` in `playback-control.blp` | `lib/amberol/primary_menu.rb` | menu | no |
| 4 | `src/volume_control.rs` + `src/gtk/volume-control.blp` | `lib/amberol/volume_control.rb` | widget | no |
| 5 | `src/playlist_view.rs` + `src/gtk/playlist-view.blp` | `lib/amberol/playlist_view.rb` | page | no |
| 6 | `src/queue_row.rs` + `src/gtk/queue-row.blp` | `lib/amberol/queue_row.rb` | row | no |
| 7 | `src/song_cover.rs` + `src/gtk/song-cover.blp` | `lib/amberol/song_cover.rb` | widget | no |
| 8 | `src/song_details.rs` + `src/gtk/song-details.blp` | `lib/amberol/song_details.rb` | widget | no |
| 9 | `src/marquee.rs` | `lib/amberol/marquee.rb` | widget | no |
| 10 | `src/waveform_view.rs` | `lib/amberol/waveform_view.rb` | widget | no |
| 11 | `src/cover_picture.rs` | `lib/amberol/cover_picture.rb` | widget | no |
| 12 | `src/drag_overlay.rs` | `lib/amberol/drag_overlay.rb` | widget | no |
| 13 | `src/gtk/shortcuts-dialog.blp` | `lib/amberol/shortcuts_dialog.rb` | shortcuts dialog | no |
| 14 | `src/search.rs` | `lib/amberol/search.rb` | filter | no |
| 15 | `src/sort.rs` | `lib/amberol/sort.rb` | sorter | no |
| 16 | `src/utils.rs` | `lib/amberol/utils.rb` | support | no |
| 17 | `src/i18n.rs` | `lib/amberol/i18n.rb` | support | no |
| 18 | `src/config.rs.in` | `lib/amberol/config.rb` | support | no |
| 19 | `src/main.rs` | `exe/amberol`, `lib/amberol.rb` | entry point | partial |
| 20 | `src/audio/mod.rs` | `lib/amberol/audio.rb` | module | no |
| 21 | `src/audio/player.rs` | `lib/amberol/audio/player.rb` | model | no |
| 22 | `src/audio/state.rs` | `lib/amberol/audio/player_state.rb` | model | no |
| 23 | `src/audio/queue.rs` | `lib/amberol/audio/queue.rb` | model | no |
| 24 | `src/audio/song.rs` | `lib/amberol/audio/song.rb` | model | no |
| 25 | `src/audio/shuffle.rs` | `lib/amberol/audio/shuffle_list_model.rb` | model | no |
| 26 | `src/audio/gst_backend.rs` | `lib/amberol/audio/gst_backend.rb` | backend | no |
| 27 | `src/audio/cover_cache.rs` | `lib/amberol/audio/cover_cache.rb` | support | no |
| 28 | `src/audio/waveform_generator.rs` | `lib/amberol/audio/waveform_generator.rb` | model | no |
| 29 | `src/audio/mpris_controller.rs` | `lib/amberol/audio/mpris_controller.rb` | integration | no |
| 30 | `src/audio/inhibit_controller.rs` | `lib/amberol/audio/inhibit_controller.rb` | integration | no |
| 31 | `src/audio/controller.rs` | `lib/amberol/audio/controller.rb` | interface | no |
| 32 | `data/io.bassi.Amberol.gschema.xml` | `lib/amberol/settings.rb` | settings | no |
| 33 | `src/gtk/style.css` | `lib/amberol/style.rb` / `data/style.css` | stylesheet | no |
| 34 | `src/amberol.gresource.xml`, `src/assets/icons/*` | `data/icons/` | resources | no |
| 35 | `po/` (54 languages) | `po/` | translations | no |

## Blockers for the port

1. **GStreamer.** All playback is `gst::Element`/`playbin` through
   `src/audio/gst_backend.rs`, including the ReplayGain element. The dev shell
   must provide the GStreamer introspection typelibs and a Ruby binding, or
   the audio layer cannot be ported at all.
2. **Tag reading.** `src/audio/song.rs` uses the `lofty` crate for metadata and
   embedded cover art. Ruby has no direct equivalent in the dev shell; a
   GStreamer discoverer or an external tool is needed.
3. **Three custom-drawn widgets.** `WaveformView` (custom `snapshot` + three
   controllers), `CoverPicture` (custom `measure`/`snapshot`) and `Marquee`
   (`Adw.TimedAnimation`-driven scroll) are GObject subclasses with vfunc
   overrides. The Ruby bindings cannot override `snapshot`/`measure`; these need
   `Gtk::DrawingArea`-based reimplementations, and the result will not be a
   literal match.
4. **MPRIS and the XDG background portal.** `mpris_controller.rs` and the
   portal request in `application.rs` need D-Bus work with no binding in the
   fork today.
5. **GSettings schema.** The port needs a compiled schema (or an in-memory
   backend) before any of the five keys can be read, and three actions
   (`win.enable-recoloring`, `app.background-play`, `win.replaygain`) are
   stateful actions backed by it.
6. **GResource.** Seventeen bundled symbolic icons are referenced by name from
   the widget tree. Without the bundle, every one of them renders as a missing
   icon; the port needs them on an icon search path instead.
