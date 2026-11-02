# frozen_string_literal: true

require "gtk4"
require_relative "config"

module Amberol
  # The application stylesheet, and the icons that go with it.
  #
  # Upstream compiles src/gtk/style.css and src/assets/icons/*.svg into a
  # GResource (src/amberol.gresource.xml) that the application registers at
  # startup. A Ruby checkout has no resource compiler, so the same two things
  # are loaded from data/: the stylesheet through a Gtk::CssProvider, and the
  # icons by adding data/icons to the icon theme's search path.
  module Style
    STYLESHEET = File.join(Config::PKGDATADIR, "style.css")
    ICON_PATH = File.join(Config::PKGDATADIR, "icons")

    # Upstream adds its recolouring provider at priority 400; the stylesheet
    # itself sits at the application priority, below it.
    APPLICATION_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION

    def self.load(display)
      unless display.nil?
        add_stylesheet(display)
        add_icons(display)
      end
      display
    end

    def self.add_stylesheet(display)
      if File.exist?(STYLESHEET)
        Gtk::StyleContext.add_provider_for_display(display, provider, APPLICATION_PRIORITY)
      end
    end

    def self.provider
      @provider ||= Gtk::CssProvider.new.tap do |css|
        css.load_from_path(STYLESHEET)
      end
    end

    # The app's own symbolic icons — the queue, selection-mode, repeat and
    # playback icons upstream ships in its resource bundle.
    def self.add_icons(display)
      if Dir.exist?(ICON_PATH)
        Gtk::IconTheme.get_for_display(display).add_search_path(ICON_PATH)
      end
    end
  end
end
