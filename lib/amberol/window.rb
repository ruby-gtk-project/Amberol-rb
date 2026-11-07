# frozen_string_literal: true

require "adwaita"
require_relative "audio"
require_relative "config"
require_relative "drag_overlay"
require_relative "i18n"
require_relative "playback_control"
require_relative "playlist_view"
require_relative "queue_row"
require_relative "search"
require_relative "settings"
require_relative "song_cover"
require_relative "song_details"
require_relative "sort"
require_relative "utils"
require_relative "waveform_view"

module Amberol
  # The main window.
  #
  # Ported from upstream's src/window.rs and src/gtk/window.blp: the initial
  # view with its three buttons, the main view with the cover, the waveform,
  # the song details and the transport controls, the playlist pane beside
  # them, the toast overlay over the lot and the drag overlay around it.
  #
  # The window owns every action in the "win" and "queue" groups, binds itself
  # to the player's state and queue, builds the playlist's filter/sort/model
  # chain, and recolours itself from the cover art.
  class Window
    # Upstream's breakpoint: below this the playlist pane collapses into an
    # overlay.
    COLLAPSE_CONDITION = "max-width: 560sp"

    # The priority upstream adds its recolouring provider at.
    RECOLOR_PRIORITY = 400

    def initialize(app, player)
      @app = app
      @player = player
      @settings = Settings.default
      @playlist_shuffled = false
      @playlist_visible = true
      @playlist_selection = false
      @playlist_search = false
      @replaygain_mode = :off
      @rows = []
    end

    attr_reader :player

    def build
      window.tap do |win|
        win.content = window_handle
        win.insert_action_group("win", win_actions)
        win.insert_action_group("queue", queue_actions)
        win.add_breakpoint(breakpoint)

        window_handle.child = drag_overlay

        drag_overlay.tap do |overlay|
          overlay.title = I18n.i18n("Drop a song to add it to the playlist")
          overlay.content = toast_overlay
        end

        toast_overlay.child = main_stack

        main_stack.tap do |stack|
          stack.transition_type = :crossfade
          stack.add_named(initial_view, "initial-view")
          stack.add_named(main_view, "main-view")
        end

        build_initial_view
        build_main_view

        setup_actions
        setup_playlist
        setup_drop_target
        setup_provider
        bind_state
        bind_queue
        bind_waveform
        connect_signals
        restore_window_state
        set_initial_state
      end
    end

    def present = window.present

    # --- Window assembly -------------------------------------------------

    def build_initial_view
      initial_view.tap do |view|
        view.add_top_bar(initial_header_bar)
        view.content = status_clamp

        status_clamp.child = status_page
        status_page.child = status_buttons_box

        status_buttons_box.tap do |box|
          box.append(restore_playlist_button)
          box.append(add_folder_button)
          box.append(add_song_button)
        end
      end
    end

    def build_main_view
      main_view.tap do |split|
        split.content = main_toolbar_view
        split.sidebar = playlist_view.build

        main_toolbar_view.tap do |view|
          view.add_top_bar(main_header_bar)
          view.content = main_box
        end

        main_box.tap do |box|
          box.append(song_cover.build)
          box.append(waveform_box)
          box.append(song_details.build)
          box.append(playback_control.build)
        end

        waveform_box.tap do |column|
          column.append(waveform_holder)
          column.append(time_box)

          waveform_holder.append(waveform_view)

          time_box.tap do |times|
            times.start_widget = elapsed_label
            times.end_widget = remaining_label
          end
        end
      end
    end

    # --- Actions ---------------------------------------------------------

    # The actions upstream installs on the window class, in the two groups the
    # accelerators and the menu name them in.
    def setup_actions
      win_actions.tap do |group|
        group.add_action(action("play") { @player.toggle_play })
        group.add_action(action("seek-backwards") { @player.seek_backwards })
        group.add_action(action("seek-forward") { @player.seek_forward })
        group.add_action(action("previous") { @player.skip_previous })
        group.add_action(action("next") { @player.skip_next })
        group.add_action(action("copy") { copy_song })
        group.add_action(action("open-directory") { open_song_directory })
        group.add_action(skip_to_action)
        group.add_action(enable_recoloring_action)
        group.add_action(replaygain_action)
      end

      queue_actions.tap do |group|
        group.add_action(action("add-song") { add_song_dialog })
        group.add_action(action("add-folder") { add_folder_dialog })
        group.add_action(action("clear") { @player.clear_queue })
        group.add_action(action("restore-playlist") { restore_playlist })
        group.add_action(action("repeat-mode") { @player.toggle_repeat_mode })
        group.add_action(toggle_action("toggle") { |value| self.playlist_visible = value })
        group.add_action(toggle_action("shuffle") { |value| self.playlist_shuffled = value })
        group.add_action(toggle_action("select") { |value| self.playlist_selection = value })
        group.add_action(toggle_action("search") { |value| self.playlist_search = value })
      end
    end

    def win_actions = @win_actions ||= Gio::SimpleActionGroup.new
    def queue_actions = @queue_actions ||= Gio::SimpleActionGroup.new

    def action(name, &block)
      Gio::SimpleAction.new(name).tap do |simple|
        simple.signal_connect("activate") { block.call }
      end
    end

    # A stateful boolean action, the way upstream's install_property_action
    # binds one to a window property.
    def toggle_action(name, &block)
      Gio::SimpleAction.new(name, nil, GLib::Variant.new(false)).tap do |simple|
        simple.signal_connect("activate") do |simple_action, _parameter|
          (!simple_action.state).then do |value|
            simple_action.state = GLib::Variant.new(value)
            block.call(value)
          end
        end
      end
    end

    def skip_to_action
      @skip_to_action ||= Gio::SimpleAction.new("skip-to", GLib::VariantType.new("u")).tap do |simple|
        simple.signal_connect("activate") do |_simple_action, parameter|
          unwrap_variant(parameter).then do |position|
            @player.skip_to(position)
            @player.play
          end
        end
      end
    end

    def enable_recoloring_action
      @enable_recoloring_action ||= Gio::SimpleAction.new(
        "enable-recoloring",
        nil,
        GLib::Variant.new(@settings.boolean("enable-recoloring")),
      ).tap do |simple|
        simple.signal_connect("activate") do |simple_action, _parameter|
          (!simple_action.state).then do |enabled|
            simple_action.state = GLib::Variant.new(enabled)
            @settings.set_boolean("enable-recoloring", enabled)
          end
        end
      end
    end

    def replaygain_action
      @replaygain_action ||= Gio::SimpleAction.new(
        "replaygain",
        GLib::VariantType.new("s"),
        GLib::Variant.new(@settings.string("replay-gain")),
      ).tap do |simple|
        simple.signal_connect("activate") do |simple_action, parameter|
          unwrap_variant(parameter).to_s.then do |nick|
            simple_action.state = GLib::Variant.new(nick)
            self.replaygain = nick.to_sym
          end
        end
      end
    end

    # A parameterised action's "activate" signal hands back the parameter
    # already unboxed to a native Ruby value (an Integer for "u", a String
    # for "s") rather than the GLib::Variant the C API documents — a
    # ruby-gnome marshalling quirk, not a value this port controls. Calling
    # `.get` on it, the way the GVariant docs would have it, raises
    # NoMethodError; this accepts either shape so a future binding fix that
    # starts handing back a real Variant keeps working too.
    def unwrap_variant(value)
      if value.respond_to?(:get)
        value.get
      else
        value
      end
    end

    def action_set_enabled(group, name, enabled)
      group.lookup_action(name).then do |found|
        unless found.nil?
          found.enabled = enabled
        end
      end
    end

    # --- Properties upstream exposes on the window -----------------------

    def playlist_visible? = @playlist_visible

    def playlist_visible=(visible)
      unless @playlist_visible == visible
        @playlist_visible = visible
        main_view.show_sidebar = visible
        sync_toggle_state("toggle", visible)
      end
      visible
    end

    def playlist_shuffled? = @playlist_shuffled

    def playlist_shuffled=(shuffled)
      unless @playlist_shuffled == shuffled
        @playlist_shuffled = shuffled
        reset_song = @player.queue.first_song? && !@player.state.playing?
        @player.queue.shuffled = shuffled
        if reset_song
          @player.skip_to(0)
        end
        sync_toggle_state("shuffle", shuffled)
      end
      shuffled
    end

    def playlist_selection? = @playlist_selection

    def playlist_selection=(selection)
      unless @playlist_selection == selection
        @playlist_selection = selection
        unless selection
          @player.queue.unselect_all_songs
        end
        @rows.each { |row| row.selection_mode = selection }
        playlist_view.queue_actionbar.revealed = selection
        update_selected_count
        sync_toggle_state("select", selection)
      end
      selection
    end

    def playlist_search? = @playlist_search

    def playlist_search=(search)
      unless @playlist_search == search
        @playlist_search = search
        if search
          self.playlist_visible = true
        end
        playlist_view.search = search
        sync_toggle_state("search", search)
      end
      search
    end

    def replaygain = @replaygain_mode

    def replaygain=(mode)
      mode.to_sym.then do |value|
        unless @replaygain_mode == value
          @replaygain_mode = value
          @player.set_replaygain(value)
          @settings.set_string("replay-gain", value.to_s)
        end
      end
      mode
    end

    # --- Queueing songs --------------------------------------------------

    # Upstream's Window::open_files, which the application's "open" handler
    # calls with the files it was given.
    def open_files(files)
      if files.empty?
        add_toast(I18n.i18n("Unable to access files"))
      else
        add_files_to_queue(files)
      end
    end

    # Walks the files handed over: audio files are queued, folders are walked
    # recursively, everything else is dropped.
    def add_files_to_queue(files)
      files.flat_map { |file| expand_file(file) }.then do |queue|
        queue_songs(queue)
      end
    end

    # Reads each file into a song from an idle callback, so a folder of a
    # thousand songs does not freeze the window while it loads.
    def queue_songs(files)
      if files.empty?
        add_toast(I18n.i18n("No available song found"))
      else
        start_loading(files)
      end
    end

    def restore_playlist
      Utils.load_cached_songs.then do |files|
        unless files.nil?
          queue_songs(files)
        end
      end
    end

    # --- Toasts ----------------------------------------------------------

    def add_toast(message)
      toast_overlay.add_toast(Adwaita::Toast.new(message))
    end

    # The toast a single added song gets, with a button that skips to it.
    def add_skip_to_toast(message, button, position)
      Adwaita::Toast.new(message).tap do |toast|
        toast.button_label = button
        toast.action_name = "win.skip-to"
        toast.action_target_value = GLib::Variant.new(position, "u")
        toast_overlay.add_toast(toast)
      end
    end

    # --- Widgets ---------------------------------------------------------

    def window
      @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
        win.title = "Amberol"
        win.set_size_request(360, 660)
        win.set_default_size(800, 600)
        win.handle_menubar_accel = true
        if Config.devel?
          win.add_css_class("devel")
        end
      end
    end

    def window_handle = @window_handle ||= Gtk::WindowHandle.new
    def drag_overlay = @drag_overlay ||= DragOverlay.new
    def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
    def main_stack = @main_stack ||= Gtk::Stack.new

    def initial_view = @initial_view ||= Adwaita::ToolbarView.new

    def initial_header_bar
      @initial_header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
        bar.show_title = false
      end
    end

    def status_clamp
      @status_clamp ||= Adwaita::Clamp.new.tap do |clamp|
        clamp.maximum_size = 450
        clamp.vexpand = true
        clamp.valign = :fill
      end
    end

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.margin_start = 12
        page.margin_end = 12
        page.title = "Amberol"
        page.description = I18n.i18n(
          "Select a file or a folder, or drag files from your file manager " \
          "to the application window to add songs to the playlist",
        )
      end
    end

    def status_buttons_box
      @status_buttons_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.halign = :center
        box.homogeneous = true
      end
    end

    def restore_playlist_button
      @restore_playlist_button ||= Gtk::Button.new(label: I18n.i18n("Restore Playlist")).tap do |button|
        button.action_name = "queue.restore-playlist"
        button.add_css_class("suggested-action")
        button.add_css_class("pill")
      end
    end

    def add_folder_button
      @add_folder_button ||= Gtk::Button.new(label: I18n.i18n("Add Folder")).tap do |button|
        button.action_name = "queue.add-folder"
        button.add_css_class("pill")
      end
    end

    def add_song_button
      @add_song_button ||= Gtk::Button.new(label: I18n.i18n("Add Song")).tap do |button|
        button.action_name = "queue.add-song"
        button.add_css_class("pill")
      end
    end

    def main_view
      @main_view ||= Adwaita::OverlaySplitView.new.tap do |split|
        split.max_sidebar_width = 330
        split.sidebar_width_fraction = 0.4
      end
    end

    def main_toolbar_view = @main_toolbar_view ||= Adwaita::ToolbarView.new

    def main_header_bar
      @main_header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
        bar.show_title = false
      end
    end

    def main_box
      @main_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
        box.valign = :center
        box.vexpand = true
        box.add_css_class("main-box")
      end
    end

    def waveform_box
      @waveform_box ||= Gtk::Box.new(:vertical, 2).tap do |box|
        box.width_request = 256
      end
    end

    def waveform_holder
      @waveform_holder ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.halign = :center
      end
    end

    def waveform_view
      @waveform_view ||= WaveformView.new.tap do |view|
        view.can_focus = true
      end
    end

    def time_box
      @time_box ||= Gtk::CenterBox.new.tap do |box|
        box.orientation = :horizontal
        box.width_request = 256
        box.halign = :center
      end
    end

    def elapsed_label
      @elapsed_label ||= Gtk::Label.new("0:00").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("numeric")
      end
    end

    def remaining_label
      @remaining_label ||= Gtk::Label.new("0:00").tap do |label|
        label.add_css_class("caption")
        label.add_css_class("numeric")
      end
    end

    def song_cover = @song_cover ||= SongCover.new
    def song_details = @song_details ||= SongDetails.new
    def playback_control = @playback_control ||= PlaybackControl.new
    def playlist_view = @playlist_view ||= PlaylistView.new

    def breakpoint
      @breakpoint ||= Adwaita::Breakpoint.new(
        Adwaita::BreakpointCondition.parse(COLLAPSE_CONDITION),
      ).tap do |point|
        point.add_setter(main_view, "collapsed", true)
      end
    end

    def provider = @provider ||= Gtk::CssProvider.new

    def filter = @filter ||= FuzzyFilter.new
    def sorter = @sorter ||= FuzzySorter.new

    # The model the list view shows: the queue's songs, filtered by the search
    # and ordered by its score.
    #
    # Upstream stacks a Gtk::FilterListModel and a Gtk::SortListModel over the
    # queue's model and wraps the pair in a selection model. Gtk::CustomSorter
    # is unusable from Ruby — its compare function receives raw pointers — so
    # the port keeps this store in step itself, applying the same filter and
    # the same comparison in #refresh_playlist_model.
    def playlist_model = @playlist_model ||= Gio::ListStore.new(Audio::Song)
    def selection_model = @selection_model ||= Gtk::NoSelection.new(playlist_model)

    # Rebuilds the visible model from the queue, the search filter and the
    # sorter, which is what upstream's filter and sort models do between them.
    def refresh_playlist_model
      @player.queue.visible_songs.select { |song| filter.match?(song) }.then do |songs|
        songs.sort { |first, second| sorter.compare(first, second) }.then do |ordered|
          # The Ruby array is the one every read goes through; the store only
          # drives the list view.
          @visible_songs = ordered
          playlist_model.remove_all
          unless ordered.empty?
            playlist_model.splice(0, 0, ordered)
          end
        end
      end
    end

    # The songs the playlist is showing, in the order it shows them.
    def visible_songs = @visible_songs ||= []

    def row_factory
      @row_factory ||= Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect("setup") { |_factory, item| setup_row(item) }
        factory.signal_connect("bind") { |_factory, item| bind_row(item) }
        factory.signal_connect("unbind") { |_factory, item| unbind_row(item) }
      end
    end

    def drop_target
      @drop_target ||= Gtk::DropTarget.new(Gdk::FileList.gtype, :copy).tap do |target|
        target.name = "file-drop-target"
        target.signal_connect("drop") do |_target, value, _x, _y|
          on_drop(value)
        end
      end
    end

    private

      # --- Loading --------------------------------------------------------

      def expand_file(file)
        file_info(file).then do |info|
          if info.nil?
            []
          else
            expand_file_type(file, info)
          end
        end
      end

      def expand_file_type(file, info)
        case info.file_type
        when Gio::FileType::DIRECTORY then Utils.load_files_from_folder(file, true)
        when Gio::FileType::REGULAR then audio_file(file, info)
        else []
        end
      end

      def audio_file(file, info)
        if info.content_type.to_s.start_with?("audio")
          [file]
        else
          []
        end
      end

      def file_info(file)
        file.query_info(
          "standard::name,standard::display-name,standard::type,standard::content-type",
          :nofollow_symlinks,
        )
      rescue GLib::Error
        nil
      end

      def start_loading(files)
        switch_mode(:main_view)
        set_loading_actions_enabled(false)
        self.playlist_visible = true
        playlist_view.begin_loading

        files.each_with_index.to_a.then do |indexed|
          songs = []
          duplicates = 0
          pending = indexed.dup

          GLib::Idle.add do
            pending.shift.then do |entry|
              if entry.nil?
                finish_loading(songs, duplicates)
                false
              else
                playlist_view.update_loading(entry.last, files.length)
                load_one(entry.first).then do |song|
                  if song.nil?
                    nil
                  elsif @player.queue.contains?(song)
                    duplicates += 1
                  else
                    songs << song
                  end
                end
                true
              end
            end
          end
        end
      end

      def load_one(file) = Audio::Song.from_uri(file.uri)

      def finish_loading(songs, duplicates)
        set_loading_actions_enabled(true)
        playlist_view.end_loading

        if songs.empty?
          if duplicates.zero?
            add_toast(I18n.i18n("No songs found"))
          end
        else
          add_loaded_songs(songs)
        end
      end

      def add_loaded_songs(songs)
        @player.queue.then do |queue|
          was_empty = queue.empty?
          queue.add_songs(songs)
          Utils.store_playlist(queue)

          if was_empty
            @player.skip_to(0)
          end

          announce_loaded(songs, was_empty)
        end
      end

      def announce_loaded(songs, was_empty)
        if songs.length == 1
          announce_one_song(was_empty)
        else
          add_toast(
            I18n.ni18n_f(
              "Added one song",
              "Added {} songs",
              songs.length,
              [songs.length.to_s],
            ),
          )
        end
      end

      def announce_one_song(was_empty)
        if was_empty
          @player.play
        else
          add_skip_to_toast(
            I18n.i18n("Added a new song"),
            I18n.i18n("Play"),
            @player.queue.n_songs - 1,
          )
        end
      end

      def set_loading_actions_enabled(enabled)
        %w[add-song add-folder clear].each do |name|
          action_set_enabled(queue_actions, name, enabled)
        end
      end

      # --- Dialogs --------------------------------------------------------

      # Upstream's "queue.add-song": a multiple-file chooser filtered to
      # audio, opening in the user's music directory.
      def add_song_dialog
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = I18n.i18n("Open File")
          dialog.accept_label = I18n.i18n("_Add Song")
          dialog.modal = true
          dialog.filters = audio_filters
          dialog.initial_folder = music_folder
          dialog.open_multiple(window) do |_source, result|
            on_files_chosen { dialog.open_multiple_finish(result) }
          end
        end
      end

      # Upstream's "queue.add-folder": the same chooser, selecting folders.
      def add_folder_dialog
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = I18n.i18n("Open Folder")
          dialog.accept_label = I18n.i18n("_Add Folder")
          dialog.modal = true
          dialog.initial_folder = music_folder
          dialog.select_multiple_folders(window) do |_source, result|
            on_files_chosen { dialog.select_multiple_folders_finish(result) }
          end
        end
      end

      # The chooser hands back a list model of files, or raises when it was
      # dismissed; an empty list is upstream's "Unable to access files".
      def on_files_chosen
        begin
          files = yield
        rescue GLib::ErrorInfo
          # Dismissing the chooser (Escape, the window's close button, or the
          # portal's own cancel) raises Gtk::DialogError::Dismissed, which is
          # not a GLib::Error despite GTK's own docs describing the finish
          # call as raising one — it shares GLib::ErrorInfo with GLib::Error
          # instead. Rescuing only GLib::Error here let a plain cancel crash
          # the app.
          files = nil
        end

        unless files.nil?
          model_items(files).then do |chosen|
            if chosen.empty?
              add_toast(I18n.i18n("Unable to access files"))
            else
              add_files_to_queue(chosen)
            end
          end
        end
      end

      def model_items(model)
        (0...model.n_items).filter_map { |position| model.get_item(position) }
      end

      def audio_filters
        Gio::ListStore.new(Gtk::FileFilter).tap do |filters|
          filters.append(
            Gtk::FileFilter.new.tap do |audio|
              audio.name = I18n.i18n("Audio files")
              audio.add_mime_type("audio/*")
            end,
          )
        end
      end

      # XDG's music directory, falling back to the working directory the way
      # upstream's glib::user_special_dir call does.
      def music_folder
        ENV.fetch("XDG_MUSIC_DIR", File.expand_path("~/Music")).then do |path|
          if Dir.exist?(path)
            Gio::File.new_for_path(path)
          else
            Gio::File.new_for_path(Dir.pwd)
          end
        end
      end

      # --- Drag and drop ---------------------------------------------------

      def setup_drop_target
        drag_overlay.drop_target = drop_target
      end

      def on_drop(value)
        file_list(value).then do |files|
          if files.empty?
            add_toast(I18n.i18n("Unable to access dropped files"))
            false
          else
            add_files_to_queue(files)
            true
          end
        end
      end

      def file_list(value)
        if value.is_a?(Gdk::FileList)
          value.files
        else
          Array(value)
        end
      rescue TypeError
        []
      end

      # --- Playlist --------------------------------------------------------

      def setup_playlist
        playlist_view.queue_view.tap do |view|
          view.model = selection_model
          view.factory = row_factory
          view.signal_connect("activate") { |_view, position| on_row_activated(position) }
        end

        playlist_view.playlist_searchentry.tap do |entry|
          entry.signal_connect("search-changed") { on_search_changed(entry) }
        end

        @player.queue.model.signal_connect("items-changed") { refresh_playlist_model }
        refresh_playlist_model
      end

      def setup_row(item)
        QueueRow.new.tap do |row|
          row.selection_mode = @playlist_selection
          row.on_selected_changed { update_selected_count }
          @rows << row
          item.child = row
        end
      end

      # Upstream binds the row's properties to the item's through property
      # expressions; the port sets them when the row is bound and keeps them
      # up to date through the song's own change listener.
      def bind_row(item)
        item.child.then do |row|
          item.item.then do |song|
            row.song = song
            apply_song_to_row(row, song)
            row.listener = song.on_change { |changed, _property| apply_song_to_row(row, changed) }
          end
        end
      end

      def unbind_row(item)
        item.child.then do |row|
          unless row.song.nil? || row.listener.nil?
            row.song.remove_listener(row.listener)
            row.listener = nil
          end
        end
      end

      def apply_song_to_row(row, song)
        row.song_title = song.title
        row.song_artist = song.artist
        row.song_cover = song.cover_texture
        row.playing = song.playing?
        row.selected = song.selected?
      end

      # A click plays the song — or, in selection mode, selects it.
      def on_row_activated(position)
        visible_songs[position].then do |song|
          unless song.nil?
            queue_position(song).then do |real_position|
              unless real_position.nil?
                activate_song_at(real_position)
              end
            end
          end
        end
      end

      def activate_song_at(position)
        if @playlist_selection
          @player.queue.select_song_at(position)
          update_selected_count
        elsif @player.queue.current_song_index == position
          @player.play
        else
          @player.skip_to(position)
          @player.play
        end
      end

      def queue_position(song)
        @player.queue.then do |queue|
          (0...queue.n_songs).find { |position| queue.song_at(position).equals?(song) }
        end
      end

      def on_search_changed(entry)
        filter.search = entry.text
        sorter.search = entry.text
        refresh_playlist_model
        playlist_view.queue_view.vadjustment.then do |adjustment|
          unless adjustment.nil?
            adjustment.value = 0.0
          end
        end
      end

      # --- Binding to the player -------------------------------------------

      def bind_state
        @player.state.then do |state|
          update_play_button
          state.on_notify(:playing) do
            self.playlist_selection = false
            update_play_button
          end

          update_position_labels
          state.on_notify(:position) { update_position_labels }

          update_song
          state.on_notify(:song) { update_song }

          update_cover
          state.on_notify(:cover) { update_cover }

          update_song_labels
          state.on_notify(:title) { update_song_labels }
          state.on_notify(:artist) { update_song_labels }
          state.on_notify(:album) { update_song_labels }

          state.on_notify(:volume) { playback_control.volume_control.volume = state.volume }
        end
      end

      def bind_queue
        @player.queue.then do |queue|
          queue.on_notify(:n_songs) { on_queue_length_changed }
          queue.on_notify(:repeat_mode) { playback_control.set_repeat_mode(queue.repeat_mode) }
          queue.on_notify(:current) { on_current_song_changed }
        end
      end

      # The waveform view shows upstream's flat line, unprompted, until the
      # generator's peaks for the current song arrive — from the cache
      # instantly, or from the analysis pipeline a little later.
      def bind_waveform
        @player.waveform_generator.on_peaks_changed do
          waveform_view.peaks = @player.waveform_generator.peaks
        end
      end

      def on_queue_length_changed
        @player.queue.then do |queue|
          if queue.empty?
            set_initial_state
            reset_queue
          else
            action_set_enabled(queue_actions, "toggle", true)
            action_set_enabled(queue_actions, "shuffle", queue.n_songs > 1)
            action_set_enabled(win_actions, "play", true)
            action_set_enabled(win_actions, "previous", true)
            action_set_enabled(win_actions, "next", queue.n_songs > 1)
          end

          if queue.n_songs == 1
            @player.skip_next
          end

          update_playlist_time
        end
      end

      def on_current_song_changed
        @player.queue.then do |queue|
          if queue.last_song? && queue.repeat_mode == :consecutive
            action_set_enabled(win_actions, "next", false)
          else
            action_set_enabled(win_actions, "next", true)
          end
        end
      end

      def connect_signals
        main_view.signal_connect("notify::collapsed") do |split, _param|
          self.playlist_visible = split.show_sidebar?
          playlist_view.back_button.visible = split.collapsed?
        end

        main_view.signal_connect("notify::show-sidebar") do |split, _param|
          self.playlist_visible = split.show_sidebar?
        end

        waveform_view.on_position_changed { |position| on_waveform_seek(position) }

        playback_control.volume_control.on_volume_changed { |volume| @player.set_volume(volume) }

        playlist_view.queue_select_all_button.signal_connect("clicked") { select_all_songs }
        playlist_view.queue_remove_button.signal_connect("clicked") { remove_selected_songs }

        playlist_view.playlist_searchbar.signal_connect("notify::search-mode-enabled") do |bar, _param|
          self.playlist_search = bar.search_mode?
        end

        @settings.connect_changed("enable-recoloring") do
          update_style(@player.state.current_song)
        end

        window.signal_connect("close-request") do
          save_window_state
          false
        end

        playlist_view.playlist_searchbar.key_capture_widget = window
      end

      def on_waveform_seek(position)
        unless @player.state.current_song.nil?
          @player.seek_position_rel(position)
          @player.play
        end
      end

      # With a search running, "select all" means the songs the search left
      # showing; without one, every song in the queue.
      def select_all_songs
        if @playlist_search
          visible_songs.each { |song| song.set_selected(true) }
        else
          @player.queue.songs.each { |song| song.set_selected(true) }
        end
        update_selected_count
      end

      def remove_selected_songs
        @player.queue.then do |queue|
          queue.selected_songs.each { |song| remove_song(song) }
          Utils.store_playlist(queue)
        end
      end

      def remove_song(song)
        @player.remove_song(song)
        update_selected_count
        update_playlist_time
      end

      # --- The state the widgets show ---------------------------------------

      def update_play_button
        if @player.state.playing?
          playback_control.play_button.icon_name = "media-playback-pause-symbolic"
        else
          playback_control.play_button.icon_name = "media-playback-start-symbolic"
        end
      end

      def update_position_labels
        @player.state.then do |state|
          if state.current_song.nil?
            set_song_time(nil, nil)
            set_song_position(0.0)
          else
            elapsed = state.position
            remaining = [state.duration - elapsed, 0].max
            set_song_time(elapsed, remaining)
            set_song_position(position_fraction(state))
          end
        end
      end

      def position_fraction(state)
        if state.duration.zero?
          0.0
        else
          state.position.to_f / state.duration
        end
      end

      def set_song_time(elapsed, remaining)
        if elapsed.nil?
          elapsed_label.text = "0:00"
        else
          elapsed_label.text = Utils.format_time(elapsed)
        end

        if remaining.nil?
          remaining_label.text = "0:00"
        else
          remaining_label.text = Utils.format_remaining_time(remaining)
        end
      end

      def set_song_position(position)
        waveform_view.position = position
      end

      def update_song
        @player.state.current_song.then do |song|
          scroll_playlist_to_song
          update_playlist_time
          update_title(song)
          update_style(song)
        end
      end

      def update_song_labels
        @player.state.then do |state|
          song_details.title_label.label_text = state.title.to_s
          song_details.artist_label.label_text = state.artist.to_s
          song_details.album_label.label_text = state.album.to_s
        end
      end

      def update_cover
        @player.state.cover.then do |cover|
          song_cover.album_image.cover = cover
          song_cover.show_cover_image(!cover.nil?)
        end
      end

      # "N minutes remaining", counting every song from the current one on.
      def update_playlist_time
        @player.queue.then do |queue|
          queue.current_song_index.then do |current|
            if current.nil?
              playlist_view.queue_length_label.visible = false
            else
              playlist_view.queue_length_label.label = remaining_time_string(queue, current)
              playlist_view.queue_length_label.visible = true
            end
          end
        end
      end

      def remaining_time_string(queue, current)
        (current...queue.n_songs).sum { |position| queue.song_at(position).duration }.then do |seconds|
          remaining_min = (seconds - (seconds % 60)) / 60
          remaining_hrs = (remaining_min - (remaining_min % 60)) / 60
          if remaining_hrs.positive?
            hours_and_minutes(remaining_hrs, remaining_min % 60)
          else
            I18n.ni18n_f(
              "{} minute remaining",
              "{} minutes remaining",
              remaining_min,
              [remaining_min.to_s],
            )
          end
        end
      end

      def hours_and_minutes(hours, minutes)
        I18n.ni18n_f(
          "{} minute",
          "{} minutes",
          minutes,
          [minutes.to_s],
        ).then do |minutes_string|
          I18n.ni18n_k(
            "{hours} hour {minutes} remaining",
            "{hours} hours {minutes} remaining",
            hours,
            [["hours", hours.to_s], ["minutes", minutes_string]],
          )
        end
      end

      def scroll_playlist_to_song
        @player.queue.current_song_index.then do |current|
          unless current.nil?
            playlist_view.queue_view.activate_action(
              "list.scroll-to-item",
              GLib::Variant.new(current, "u"),
            )
          end
        end
      end

      def update_title(song)
        if song.nil?
          window.title = "Amberol"
        else
          window.title = "#{song.artist} - #{song.title}"
        end
      end

      def update_selected_count
        @player.queue.n_selected_songs.then do |n_selected|
          if n_selected.zero?
            playlist_view.queue_selected_label.label = I18n.i18n("No song selected")
          else
            playlist_view.queue_selected_label.label = I18n.ni18n_f(
              "{} song selected",
              "{} songs selected",
              n_selected,
              [n_selected.to_s],
            )
          end
        end
      end

      # --- Recolouring -------------------------------------------------------

      def setup_provider
        Gdk::Display.default.then do |display|
          unless display.nil?
            Gtk::StyleContext.add_provider_for_display(display, provider, RECOLOR_PRIORITY)
          end
        end
      end

      # Turns the cover's palette into the --background-color-N variables the
      # stylesheet gradients read, or clears them when there is no cover or
      # recolouring is off.
      def update_style(song)
        if @settings.boolean("enable-recoloring")
          apply_palette(song&.cover_palette)
        else
          clear_style
        end
      end

      def apply_palette(palette)
        if palette.nil? || palette.empty?
          clear_style
          action_set_enabled(win_actions, "enable-recoloring", false)
        else
          provider.load_from_string(palette_css(palette))
          unless main_stack.css_classes.include?("main-window")
            main_stack.add_css_class("main-window")
          end
          action_set_enabled(win_actions, "enable-recoloring", true)
        end
      end

      def palette_css(palette)
        palette.each_with_index.map do |colour, index|
          "--background-color-#{index}: #{colour};"
        end.then do |declarations|
          (palette.length...5).each do |index|
            declarations << "--background-color-#{index}: var(--window-bg-color);"
          end
          ":root {#{declarations.join}}"
        end
      end

      def clear_style
        provider.load_from_string("")
        main_stack.remove_css_class("main-window")
      end

      # --- Window state ------------------------------------------------------

      def restore_window_state
        window.set_default_size(@settings.int("window-width"), @settings.int("window-height"))
      end

      def save_window_state
        window.default_size.then do |(width, height)|
          @settings.set_int("window-width", width)
          @settings.set_int("window-height", height)
        end
      end

      def reset_queue
        self.playlist_visible = false
        self.playlist_shuffled = false
        self.playlist_selection = false
        update_style(nil)
      end

      # Upstream's set_initial_state: which actions are live, which view shows,
      # and whether the "Restore Playlist" button is the suggested one.
      def set_initial_state
        @player.queue.then do |queue|
          action_set_enabled(win_actions, "play", !queue.empty?)
          action_set_enabled(win_actions, "previous", !queue.empty?)
          action_set_enabled(win_actions, "next", !queue.last_song?)
          action_set_enabled(queue_actions, "toggle", !queue.empty?)
          action_set_enabled(queue_actions, "shuffle", queue.n_songs > 1)
          action_set_enabled(win_actions, "replaygain", @player.replaygain_available?)

          self.replaygain = Audio.replay_gain_mode(@settings.enum("replay-gain"))
          @player.set_replaygain(@replaygain_mode)

          playback_control.set_repeat_mode(queue.repeat_mode)
          self.playlist_shuffled = queue.shuffled?

          status_page.icon_name = Config::APPLICATION_ID

          update_restore_button
          update_initial_mode(queue)
        end
      end

      def update_restore_button
        if Utils.has_cached_playlist?
          restore_playlist_button.visible = true
          restore_playlist_button.add_css_class("suggested-action")
          add_folder_button.remove_css_class("suggested-action")
        else
          restore_playlist_button.visible = false
          restore_playlist_button.remove_css_class("suggested-action")
          add_folder_button.add_css_class("suggested-action")
        end
      end

      def update_initial_mode(queue)
        if @player.state.playing? || !queue.empty?
          switch_mode(:main_view)
        else
          switch_mode(:initial_view)
        end
      end

      def switch_mode(mode)
        case mode
        when :initial_view
          main_stack.visible_child_name = "initial-view"
          window.default_widget = add_folder_button
        else
          main_stack.visible_child_name = "main-view"
          window.default_widget = playback_control.play_button
        end
      end

      # Keeps a toggle action's state in step when the property is changed
      # from somewhere other than the action — a collapsed split view, say.
      def sync_toggle_state(name, value)
        queue_actions.lookup_action(name).then do |found|
          unless found.nil? || found.state == value
            found.state = GLib::Variant.new(value)
          end
        end
      end

      # --- The menu's two one-off actions -------------------------------------

      def copy_song
        @player.state.current_song.then do |song|
          unless song.nil?
            # Gdk::Clipboard#set takes the value directly in these bindings;
            # there is no set_text.
            window.clipboard.set(
              I18n.i18n_k(
                "Currently playing “{title}” by “{artist}”",
                [["title", song.title], ["artist", song.artist]],
              ),
            )
          end
        end
      end

      def open_song_directory
        @player.state.current_song.then do |song|
          unless song.nil?
            Gtk::FileLauncher.new(song.file).open_containing_folder(window) do |_source, _result|
              nil
            end
          end
        end
      rescue GLib::Error
        add_toast(I18n.i18n("Unable to open folder"))
      end
  end
end
