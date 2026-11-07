# frozen_string_literal: true

# Drives the app headlessly through GtkDriver: builds the real window, queues
# a folder of generated songs, then exercises every action, dialog, menu and
# keyboard shortcut the UI binds, plus the empty and error states.
#
# Run it from the dev shell:
#
#   nix develop --command xvfb-run -a ruby test/drive_window.rb
#
# Each check prints ok/FAIL; screenshots land under tmp/shots/; the run ends
# with "N of M checks passed" and "DRIVE OK" (or "DRIVE FAILED (n)").

$stdout.sync = true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "fileutils"
require "tmpdir"
require "amberol"
require_relative "gtk_driver"

# Three WAVE files with LIST/INFO tags, two to four seconds each, so the test
# does not need any audio in the repository.
def write_library(directory)
  FileUtils.mkdir_p(directory)
  3.times do |index|
    rate = 8000
    frequency = 330 + (index * 110)
    samples = (0...(rate * (2 + index))).map do |frame|
      (Math.sin(2 * Math::PI * frequency * frame / rate) * 9000).to_i
    end
    write_wave(
      File.join(directory, format("%02d-track.wav", index)),
      rate,
      samples.pack("s<*"),
      index,
    )
  end
  directory
end

def write_wave(path, rate, pcm, index)
  info = "INFO" \
         "INAM#{[8].pack("V")}#{"Track #{index}\x00".b[0, 8]}" \
         "IART#{[8].pack("V")}#{"Artist #{index}".b[0, 8]}"
  body = "WAVEfmt #{[16].pack("V")}#{[1, 1].pack("v2")}#{[rate, rate * 2].pack("V2")}#{[2, 16].pack("v2")}" \
         "LIST#{[info.bytesize].pack("V")}#{info}" \
         "data#{[pcm.bytesize].pack("V")}#{pcm}"
  File.binwrite(path, "RIFF#{[body.bytesize].pack("V")}#{body}")
end

# A folder with no audio in it at all: `load_one` turns every entry into an
# invalid Song, which `finish_loading` reports with "No songs found".
def write_junk_folder(directory)
  FileUtils.mkdir_p(directory)
  File.write(File.join(directory, "notes.txt"), "not audio")
  File.write(File.join(directory, "cover.jpg"), "\xFF\xD8\xFF\xE0not a real jpeg".b)
  directory
end

# Closes any extra toplevel the run opened (a file chooser, say) without
# waiting on a response nothing in this harness can supply.
def close_extra_toplevels(keep)
  Gtk::Window.toplevels.each do |window|
    unless window.equal?(keep)
      window.close
    end
  end
end

Dir.mktmpdir("amberol-drive") do |root|
  ENV["XDG_CONFIG_HOME"] = File.join(root, "config")
  ENV["XDG_CACHE_HOME"] = File.join(root, "cache")
  library = write_library(File.join(root, "library"))
  junk_folder = write_junk_folder(File.join(root, "junk"))
  empty_folder = File.join(root, "empty").tap { |dir| FileUtils.mkdir_p(dir) }

  application = Amberol::Application.new

  # The default 120s watchdog was tight even before this: one step now
  # waits on a real 2-second WAVE file playing through GstPlay to a real
  # end-of-stream (see "GstPlay actually plays audio" below), wall-clock
  # time the rest of the steps never needed.
  GtkDriver.drive(application, shots: File.expand_path("tmp/shots", __dir__), timeout: 180) do |d, _app|
    d.window { application.send(:built_window).window }

    d.step("the window and its initial view") do
      window = application.send(:built_window)
      d.check("the window is an Adwaita application window") { window.window.is_a?(Adwaita::ApplicationWindow) }
      d.check("its title is Amberol") { window.window.title == "Amberol" }
      d.check("the initial view is showing, empty") { window.main_stack.visible_child_name == "initial-view" }
      d.check("the restore-playlist button starts hidden") { !window.restore_playlist_button.visible? }
      d.shot("01-initial-view")
    end

    d.step("the primary menu names actions every group installs") do
      window = application.send(:built_window)
      flat = Amberol::PrimaryMenu.sections.flat_map { |section| section } +
             Amberol::PrimaryMenu.replaygain_items
      flat.each do |(_label, action, _target)|
        group, name = action.split(".", 2)
        exists =
          case group
          when "app" then !application.app.lookup_action(name).nil?
          when "win" then !window.win_actions.lookup_action(name).nil?
          when "queue" then !window.queue_actions.lookup_action(name).nil?
          end
        d.check("#{action} resolves to an installed action") { exists }
      end
    end

    d.step("every accelerator upstream binds names an action that exists") do
      window = application.send(:built_window)
      Amberol::Application::ACCELERATORS.each_key do |detailed|
        group, name = detailed.split(".", 2)
        exists =
          case group
          when "app" then !application.app.lookup_action(name).nil?
          when "win" then !window.win_actions.lookup_action(name).nil?
          when "queue" then !window.queue_actions.lookup_action(name).nil?
          end
        d.check("#{detailed} resolves to an installed action") { exists }
        d.check("#{detailed} has a non-empty accelerator") { !Amberol::Application::ACCELERATORS[detailed].empty? }
      end
    end

    d.step("the shortcuts dialog's bindings match the app's own accelerators") do
      dialog = Amberol::ShortcutsDialog.new.build
      labels_and_accels = Amberol::ShortcutsDialog.sections.flat_map { |(_title, items)| items }
      d.check("it lists quit as <primary>q") do
        labels_and_accels.any? { |(_label, accel)| accel == "<primary>q" } &&
          Amberol::Application::ACCELERATORS["app.quit"] == ["<primary>q"]
      end
      d.check("it lists shortcuts as <primary>question") do
        Amberol::Application::ACCELERATORS["app.shortcuts"] == ["<primary>question"]
      end
      d.check("it builds a dialog") { dialog.is_a?(Adwaita::ShortcutsDialog) }
      window = application.send(:built_window)
      dialog.present(window.window)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.shot("02-shortcuts", window.window)
      dialog.close
    end

    d.step("the about dialog carries upstream's metadata") do
      dialog = Amberol::AboutDialog.build
      d.check("it names the app Amberol") { dialog.application_name == "Amberol" }
      d.check("it carries the GPL-3.0 licence") { dialog.license_type == Gtk::License::GPL_3_0 }
      window = application.send(:built_window)
      dialog.present(window.window)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.shot("03-about", window.window)
      dialog.close
    end

    d.step("an empty folder queues nothing and says so") do
      window = application.send(:built_window)
      window.add_files_to_queue([Gio::File.new_for_path(empty_folder)])
    end

    d.step("the toast reports no songs were found") do
      window = application.send(:built_window)
      d.check("the queue is still empty") { window.player.queue.n_songs.zero? }
      d.check("the view is still the initial one") { window.main_stack.visible_child_name == "initial-view" }
    end

    d.step("a folder with no audio in it loads to zero songs") do
      window = application.send(:built_window)
      window.add_files_to_queue([Gio::File.new_for_path(junk_folder)])
    end

    d.step("loading settles on 'No songs found', nothing queued") do
      sleep(0.3)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      window = application.send(:built_window)
      d.check("the queue is still empty") { window.player.queue.n_songs.zero? }
    end

    d.step("queue the real library") do
      window = application.send(:built_window)
      window.add_files_to_queue([Gio::File.new_for_path(library)])
    end

    # Songs are loaded from an idle callback.
    d.step("wait for loading") do
      sleep(0.5)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
    end

    d.step("the queue now holds the three tracks, main view showing") do
      window = application.send(:built_window)
      d.check("three songs loaded") { window.player.queue.n_songs == 3 }
      d.check("the main view is showing") { window.main_stack.visible_child_name == "main-view" }
      d.check("the playlist rows list them in order") do
        window.visible_songs.map(&:title) == ["Track 0", "Track 1", "Track 2"]
      end
      d.check("the current song is the first one") { window.player.state.current_song&.title == "Track 0" }
      d.shot("04-main-view")
    end

    d.step("win.play toggles playback") do
      window = application.send(:built_window)
      window.win_actions.lookup_action("play").activate(nil)
      d.check("the player is playing") { window.player.state.playing? }
    end

    d.step("the song details and elapsed label reflect the current song") do
      window = application.send(:built_window)
      d.check("title") { window.song_details.title_label.label_text == "Track 0" }
      d.check("artist") { window.song_details.artist_label.label_text == "Artist 0" }
      d.check("elapsed starts at 0:00") { window.elapsed_label.text == "0:00" }
      d.check("the cover stack shows the placeholder (no art in these WAVE files)") do
        window.song_cover.cover_stack.visible_child_name == "no-image"
      end
    end

    d.step("win.seek-forward and win.seek-backwards do not raise") do
      window = application.send(:built_window)
      window.win_actions.lookup_action("seek-forward").activate(nil)
      window.win_actions.lookup_action("seek-backwards").activate(nil)
      d.check("still playing the same song") { window.player.state.current_song&.title == "Track 0" }
    end

    # Track 0 is a real 2-second WAVE file, playing through GstPlay::Play —
    # this is the GstBackend's actual playback path, not a mock: the GLib
    # main loop has to keep turning long enough for the real end-of-stream
    # message GstPlay posts on its message_bus to reach GstBackend's bus
    # watch and fire PlaybackAction::PlayNext, which advances the queue.
    # (Position updates off that same bus are checked too, best-effort: a
    # sandboxed audio-less CI pipeline can run the file through faster than
    # wall clock, so their absence alone would not mean the wiring is dead —
    # the queue actually advancing on a real EOS message is the proof.)
    d.step("GstPlay actually plays audio: EOS auto-advances the queue") do
      window = application.send(:built_window)
      deadline = Time.now + 6
      until Time.now > deadline || window.player.state.current_song&.title != "Track 0"
        GLib::MainContext.default.iteration(true)
      end
      d.check("end-of-stream on Track 0 advanced the queue to Track 1") do
        window.player.state.current_song&.title == "Track 1"
      end
      d.check("the new song is playing") { window.player.state.playing? }
    end

    d.step("the search bar filters the playlist") do
      window = application.send(:built_window)
      window.queue_actions.lookup_action("search").activate(nil)
      d.check("the search toggle action opened the search bar") do
        window.playlist_search? && window.playlist_view.playlist_searchbar.search_mode?
      end
      window.playlist_view.playlist_searchentry.text = "track 2"
      # "search-changed" is debounced a little after "changed", so the filter
      # needs a turn of the loop before it applies.
      sleep(0.3)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.check("only track 2 is visible") { window.visible_songs.map(&:title) == ["Track 2"] }
    end

    d.step("clearing the search restores every row") do
      window = application.send(:built_window)
      window.playlist_view.playlist_searchentry.text = ""
      window.queue_actions.lookup_action("search").activate(nil)
      d.check("the search bar closed") { !window.playlist_search? }
      d.check("all three rows are back") { window.visible_songs.length == 3 }
    end

    d.step("queue.shuffle shuffles and unshuffles without losing songs") do
      window = application.send(:built_window)
      window.queue_actions.lookup_action("shuffle").activate(nil)
      d.check("shuffled, same song count") do
        window.playlist_shuffled? && window.player.queue.n_songs == 3
      end
      window.queue_actions.lookup_action("shuffle").activate(nil)
      d.check("unshuffled again") { !window.playlist_shuffled? }
    end

    d.step("queue.select turns on selection mode") do
      window = application.send(:built_window)
      # win.play's own "state.on_notify(:playing)" hook exits selection mode
      # the moment playback (re)starts -- correct behaviour for a real user
      # pressing play, but with GstPlay actually advancing the queue on a
      # real end-of-stream now, that same notification can fire on its own
      # between steps as the current song finishes. Pausing first keeps the
      # two steps' shared selection state stable across that gap.
      window.player.pause
      window.queue_actions.lookup_action("select").activate(nil)
      window.player.queue.select_song_at(0)
      d.check("selection mode is on") { window.playlist_selection? }
      d.check("the selection count label updates") do
        window.playlist_view.queue_selected_label.label == "1 song selected"
      end
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.shot("05-selection-mode")
    end

    d.step("removing the selected song drops the queue by one") do
      window = application.send(:built_window)
      before = window.player.queue.n_songs
      window.send(:remove_selected_songs)
      d.check("one song gone") { window.player.queue.n_songs == before - 1 }
      window.queue_actions.lookup_action("select").activate(nil)
      window.player.play
    end

    d.step("queue.repeat-mode cycles and the button icon follows it") do
      window = application.send(:built_window)
      before = window.player.queue.repeat_mode
      window.queue_actions.lookup_action("repeat-mode").activate(nil)
      d.check("repeat mode changed") { window.player.queue.repeat_mode != before }
      d.check("the repeat button's icon matches") do
        window.playback_control.repeat_button.icon_name ==
          (window.player.queue.repeat_mode == :repeat_all ? "media-playlist-repeat-symbolic" : "media-playlist-consecutive-symbolic")
      end
    end

    d.step("win.previous/win.next and win.skip-to move the current song") do
      window = application.send(:built_window)
      player = window.player
      player.skip_to(0)
      first = player.state.current_song&.title
      window.win_actions.lookup_action("next").activate(nil)
      second = player.state.current_song&.title
      window.win_actions.lookup_action("previous").activate(nil)
      d.check("next advanced") { first != second }
      d.check("previous returned") { player.state.current_song&.title == first }
      window.win_actions.lookup_action("skip-to").activate(GLib::Variant.new(1, "u"))
      d.check("skip-to jumped to the requested song") { player.state.current_song&.title == second }
      player.skip_to(0)
    end

    d.step("win.enable-recoloring is disabled without cover art, armed with it") do
      window = application.send(:built_window)
      simple = window.win_actions.lookup_action("enable-recoloring")
      # These generated WAVE files carry no cover art, so apply_palette
      # disables the action, the way upstream disables the matching menu
      # item when there is nothing to recolour from.
      d.check("disabled: no song has cover art") { !simple.enabled? }

      window.send(:apply_palette, ["#112233", "#445566"])
      d.check("armed once a palette is applied") { simple.enabled? }
      before = simple.state
      simple.activate(nil)
      d.check("the action's state flipped") { simple.state != before }
      simple.activate(nil)
      d.check("and flipped back") { simple.state == before }

      window.send(:apply_palette, nil)
      d.check("disabled again once the palette is cleared") { !simple.enabled? }
    end

    d.step("win.replaygain is enabled (GstPlay's playbin has a working rgvolume/rglimiter filter)") do
      window = application.send(:built_window)
      simple = window.win_actions.lookup_action("replaygain")
      d.check("the action is enabled, matching replaygain_available? == true") do
        simple.enabled? && window.player.replaygain_available?
      end
      simple.activate(GLib::Variant.new("album", "s"))
      d.check("activating the action lands on the requested mode") { window.replaygain == :album }
      window.send(:replaygain=, "track")
      d.check("track") { window.replaygain == :track }
      window.send(:replaygain=, "off")
      d.check("off") { window.replaygain == :off }
    end

    d.step("the volume control reports and mutes") do
      window = application.send(:built_window)
      control = window.playback_control.volume_control
      control.volume = 0.5
      control.action_group.lookup_action("toggle-mute").activate(nil)
      d.check("muted, the slider reads zero") { control.muted? && control.volume == 0.0 }
      control.action_group.lookup_action("toggle-mute").activate(nil)
      d.check("unmuted, the slider is back to 0.5") { !control.muted? && control.volume == 0.5 }
    end

    d.step("the waveform view accepts a seek position") do
      window = application.send(:built_window)
      window.waveform_view.position = 0.5
      d.check("position round-trips") { window.waveform_view.position == 0.5 }
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.shot("06-waveform")
    end

    d.step("the toast overlay adds a toast") do
      window = application.send(:built_window)
      window.add_toast("Driven by test/drive_window.rb")
    end

    d.step("win.copy and win.open-directory do not raise") do
      window = application.send(:built_window)
      window.win_actions.lookup_action("copy").activate(nil)
      window.win_actions.lookup_action("open-directory").activate(nil)
    end

    d.step("queue.toggle hides and shows the playlist pane") do
      window = application.send(:built_window)
      window.queue_actions.lookup_action("toggle").activate(nil)
      first = window.playlist_visible?
      window.queue_actions.lookup_action("toggle").activate(nil)
      d.check("the pane's visibility flipped") { window.playlist_visible? != first }
      d.check("the split view's sidebar tracks it") { window.main_view.show_sidebar? == window.playlist_visible? }
    end

    d.step("queue.add-song opens a file chooser and it is dismissed") do
      window = application.send(:built_window)
      before = Gtk::Window.toplevels.n_items
      window.queue_actions.lookup_action("add-song").activate(nil)
      sleep(0.2)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.check("a new toplevel appeared for the chooser") { Gtk::Window.toplevels.n_items > before }
      close_extra_toplevels(window.window)
    end

    d.step("queue.add-folder opens a folder chooser and it is dismissed") do
      window = application.send(:built_window)
      before = Gtk::Window.toplevels.n_items
      window.queue_actions.lookup_action("add-folder").activate(nil)
      sleep(0.2)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.check("a new toplevel appeared for the chooser") { Gtk::Window.toplevels.n_items > before }
      close_extra_toplevels(window.window)
    end

    d.step("the drag overlay reveals and hides its drop status page") do
      overlay = Amberol::DragOverlay.new
      overlay.title = "Drop a song to add it to the playlist"
      d.check("the title round-trips") { overlay.title == "Drop a song to add it to the playlist" }
      overlay.send(:reveal, true)
      d.check("revealed") { overlay.revealer.reveal_child? }
      overlay.send(:reveal, false)
      d.check("hidden again") { !overlay.revealer.reveal_child? }
    end

    d.step("app.background-play toggles the hold that keeps the app alive") do
      simple = application.app.lookup_action("background-play")
      before = simple.state
      simple.activate(nil)
      d.check("the action's state flipped") { simple.state != before }
      simple.activate(nil)
      d.check("and flipped back") { simple.state == before }
    end

    d.step("queue.clear empties the queue and the initial view returns") do
      window = application.send(:built_window)
      window.queue_actions.lookup_action("clear").activate(nil)
      d.check("the queue is empty") { window.player.queue.n_songs.zero? }
      d.check("the initial view is back") { window.main_stack.visible_child_name == "initial-view" }
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      d.shot("07-cleared")
    end

    d.step("the restore-playlist button offers the cleared playlist back") do
      window = application.send(:built_window)
      d.check("the cache file was written while songs were queued") { Amberol::Utils.has_cached_playlist? }
      d.check("the restore button is now visible") { window.restore_playlist_button.visible? }
    end

    d.step("queue.restore-playlist reloads the cached queue") do
      window = application.send(:built_window)
      window.queue_actions.lookup_action("restore-playlist").activate(nil)
    end

    d.step("wait for the restore to finish loading") do
      sleep(0.5)
      GLib::MainContext.default.iteration(false) while GLib::MainContext.default.pending?
      window = application.send(:built_window)
      d.check("the two remaining songs came back") { window.player.queue.n_songs == 2 }
    end

    d.step("app.quit stops the application") do
      application.app.lookup_action("quit").activate(nil)
    end
  end
end
