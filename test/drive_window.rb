# frozen_string_literal: true

# Drives the app headlessly: builds the window, queues a folder of generated
# songs, then exercises the actions the UI binds — play, search, shuffle,
# selection mode, removal, repeat, volume, mute, the toast overlay, the
# clipboard, the playlist pane and clearing the queue.
#
# Run it from the dev shell:
#
#   nix develop --command xvfb-run -a ruby test/drive_window.rb
#
# Every step prints OK or FAIL; the exit status is non-zero if any step failed.

$stdout.sync = true
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "fileutils"
require "tmpdir"
require "amberol"

FAILURES = []

def step(label)
  puts "OK   #{label}: #{yield.inspect}"
rescue Exception => error # rubocop:disable Lint/RescueException
  FAILURES << label
  puts "FAIL #{label}: #{error.class}: #{error.message}"
  puts "     #{error.backtrace.first(4).join("\n     ")}"
end

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

def exercise(window, app)
  step("queue loaded") { [window.player.queue.n_songs, window.main_stack.visible_child_name] }
  step("playlist rows") { window.visible_songs.map(&:title) }
  step("current song") { window.player.state.current_song&.title }
  step("play") do
    window.win_actions.lookup_action("play").activate(nil)
    window.player.state.playing?
  end
  step("song details") do
    [
      window.song_details.title_label.label_text,
      window.song_details.artist_label.label_text,
      window.elapsed_label.text,
    ]
  end
  step("search filters") do
    window.filter.search = "track 2"
    window.refresh_playlist_model
    window.visible_songs.map(&:title)
  end
  step("search cleared") do
    window.filter.search = ""
    window.refresh_playlist_model
    window.visible_songs.length
  end
  step("shuffle") do
    window.queue_actions.lookup_action("shuffle").activate(nil)
    shuffled = [window.playlist_shuffled?, window.player.queue.n_songs]
    window.queue_actions.lookup_action("shuffle").activate(nil)
    shuffled + [window.playlist_shuffled?]
  end
  step("selection mode") do
    window.queue_actions.lookup_action("select").activate(nil)
    window.player.queue.select_song_at(0)
    [window.playlist_selection?, window.playlist_view.queue_selected_label.label]
  end
  step("remove selected") do
    before = window.player.queue.n_songs
    window.send(:remove_selected_songs)
    [before, window.player.queue.n_songs]
  end
  step("repeat mode") do
    window.queue_actions.lookup_action("repeat-mode").activate(nil)
    [window.player.queue.repeat_mode, window.playback_control.repeat_button.icon_name]
  end
  step("skip next and previous") do
    player = window.player
    player.skip_to(0)
    first = player.state.current_song&.title
    player.skip_next
    second = player.state.current_song&.title
    player.skip_previous
    [first, second, player.state.current_song&.title]
  end
  step("volume and mute") do
    control = window.playback_control.volume_control
    control.volume = 0.5
    control.action_group.lookup_action("toggle-mute").activate(nil)
    [control.muted?, control.volume]
  end
  step("waveform position") do
    window.waveform_view.position = 0.5
    window.waveform_view.position
  end
  step("toast") do
    window.add_toast("Driven by test/drive_window.rb")
    "added"
  end
  step("copy song") do
    window.win_actions.lookup_action("copy").activate(nil)
    "copied"
  end
  step("playlist pane") do
    window.queue_actions.lookup_action("toggle").activate(nil)
    [window.playlist_visible?, window.main_view.show_sidebar?]
  end
  step("about dialog") { Amberol::AboutDialog.build.class }
  step("shortcuts dialog") { Amberol::ShortcutsDialog.new.build.class }
  step("clear queue") do
    window.queue_actions.lookup_action("clear").activate(nil)
    [window.player.queue.n_songs, window.main_stack.visible_child_name]
  end
  app.quit
end

Dir.mktmpdir("amberol-drive") do |root|
  ENV["XDG_CONFIG_HOME"] = File.join(root, "config")
  library = write_library(File.join(root, "library"))

  application = Amberol::Application.new
  app = application.build

  # A watchdog, so a hung step cannot hang the run.
  GLib::Timeout.add(40_000) do
    FAILURES << "watchdog"
    puts "FAIL watchdog: the run did not finish"
    app.quit
    false
  end

  app.signal_connect("activate") do
    GLib::Idle.add do
      window = application.send(:built_window)
      step("window") { [window.window.class, window.window.title] }
      step("initial view") { window.main_stack.visible_child_name }
      step("queue a folder") do
        window.add_files_to_queue([Gio::File.new_for_path(library)])
        "queued"
      end

      # Songs are loaded from an idle callback, so the rest of the run waits
      # for the loading to finish.
      GLib::Timeout.add(800) do
        exercise(window, app)
        false
      end
      false
    end
  end

  app.run([])
end

if FAILURES.empty?
  puts "DONE: every step passed"
else
  puts "DONE: #{FAILURES.length} step(s) failed: #{FAILURES.join(", ")}"
end

exit(FAILURES.empty? ? 0 : 1)
