# frozen_string_literal: true

require "adwaita"
require "gtk4"
require_relative "about_dialog"
require_relative "audio"
require_relative "config"
require_relative "i18n"
require_relative "settings"
require_relative "shortcuts_dialog"
require_relative "style"
require_relative "window"

module Amberol
  # The application.
  #
  # Ported from upstream's src/application.rs and src/main.rs: it owns the
  # audio player, opens the one window, installs the app-level actions and the
  # accelerators, and holds the application alive while background playback is
  # enabled.
  #
  # Upstream subclasses adw::Application; the Ruby bindings cannot subclass it
  # usefully, so the application object is composed instead — the same shape
  # the ruby-gtk house style uses, with every widget a memoized method and the
  # assembly in #build.
  class Application
    # Upstream's accelerators, from Application::constructed.
    ACCELERATORS = {
      "app.quit"           => ["<primary>q"],
      "app.shortcuts"      => ["<primary>question"],
      "queue.add-song"     => ["<primary>s"],
      "queue.add-folder"   => ["<primary>a"],
      "queue.clear"        => ["<primary><shift>l"],
      "queue.toggle"       => ["F9"],
      "queue.search"       => ["<primary><shift>f"],
      "queue.shuffle"      => ["<primary>r"],
      "win.seek-backwards" => ["<primary>Left"],
      "win.seek-forward"   => ["<primary>Right"],
      "win.previous"       => ["<primary>b"],
      "win.next"           => ["<primary>n"],
      "win.play"           => ["<primary>p"],
      "win.copy"           => ["<primary>c"],
    }.freeze

    def build
      app.tap do |application|
        I18n.bind_text_domain

        application.signal_connect("startup") do
          Gtk::Window.set_default_icon_name(Config::APPLICATION_ID)
          Style.load(Gdk::Display.default)
        end

        application.signal_connect("activate") { present_main_window }

        application.signal_connect("open") do |_application, files, _hint|
          present_main_window
          window.open_files(Array(files))
        end

        setup_actions
        setup_accelerators
        setup_settings
      end
    end

    def run(argv = ARGV) = app.run(argv)

    def player = @player ||= Audio::AudioPlayer.new(method(:process_action))

    # Upstream's ApplicationAction channel carries exactly one action: Present,
    # which the MPRIS controller uses to raise the window.
    def process_action(action, *_args)
      case action
      when :present then present_main_window
      end
    end

    # Adwaita::Application is best avoided in the Ruby bindings; the
    # application object comes from Gtk, and HANDLES_OPEN is the flag upstream
    # builds with so files can be opened into the queue.
    def app
      @app ||= Gtk::Application.new(Config::APPLICATION_ID, :handles_open).tap do
        Adwaita.init
      end
    end

    def window = @window ||= Window.new(app, player)

    def settings = @settings ||= Settings.default

    def setup_actions
      app.add_action(action("quit") { app.quit })
      app.add_action(action("about") { show_about })
      app.add_action(action("shortcuts") { show_shortcuts })
      app.add_action(background_play_action)
    end

    def setup_accelerators
      ACCELERATORS.each do |name, accelerators|
        app.set_accels_for_action(name, accelerators)
      end
    end

    # Background playback holds the application alive while the window is
    # closed; upstream also asks the portal for permission, which only applies
    # to a sandboxed build.
    def setup_settings
      settings.connect_changed("background-play") do |store, _key|
        apply_background_play(store.boolean("background-play"))
      end
      apply_background_play(settings.boolean("background-play"))
    end

    def action(name, &block)
      Gio::SimpleAction.new(name).tap do |simple|
        simple.signal_connect("activate") { block.call }
      end
    end

    def background_play_action
      @background_play_action ||= Gio::SimpleAction.new(
        "background-play",
        nil,
        GLib::Variant.new(settings.boolean("background-play")),
      ).tap do |simple|
        simple.signal_connect("activate") do |simple_action, _parameter|
          (!simple_action.state).then do |enabled|
            simple_action.state = GLib::Variant.new(enabled)
            settings.set_boolean("background-play", enabled)
          end
        end
      end
    end

    private

      def present_main_window
        built_window.present
      end

      # The window is built once, on the first activation.
      def built_window
        @built_window ||= window.tap { |win| win.build }
      end

      def apply_background_play(enabled)
        if enabled
          if @background_hold.nil?
            @background_hold = true
            app.hold
          end
        else
          unless @background_hold.nil?
            @background_hold = nil
            app.release
          end
        end
      end

      def show_about
        AboutDialog.build.present(window.window)
      end

      def show_shortcuts
        ShortcutsDialog.new.build.present(window.window)
      end
  end
end
