# frozen_string_literal: true

require "adwaita"
require_relative "i18n"

module Amberol
  # The playlist pane.
  #
  # Ported from upstream's src/playlist_view.rs and src/gtk/playlist-view.blp:
  # a header bar with the search and selection toggles and the queue length,
  # a search bar, the queue's list view under a loading progress bar, and the
  # selection-mode action bar along the bottom.
  class PlaylistView
    def build
      root.tap do |view|
        view.add_top_bar(header_bar)
        view.add_top_bar(playlist_searchbar)
        view.content = playlist_overlay
        view.add_bottom_bar(queue_actionbar)

        header_bar.tap do |bar|
          bar.pack_start(search_button)
          bar.title_widget = queue_length_box
          bar.pack_end(back_button)
          bar.pack_end(select_button)

          queue_length_box.tap do |box|
            box.append(playlist_label)
            box.append(queue_length_label)
          end
        end

        playlist_searchbar.tap do |bar|
          bar.child = playlist_searchentry
          bar.connect_entry(playlist_searchentry)
        end

        playlist_overlay.tap do |overlay|
          overlay.child = scroller
          overlay.add_overlay(playlist_progress)

          scroller.child = queue_view
        end

        queue_actionbar.tap do |bar|
          bar.pack_start(queue_select_all_button)
          bar.center_widget = queue_selected_label
          bar.pack_end(queue_remove_button)
        end
      end
    end

    # --- Loading progress, from upstream's PlaylistView ------------------

    def begin_loading
      playlist_progress.fraction = 0.0
      playlist_progress.visible = true
    end

    def end_loading
      playlist_progress.visible = false
    end

    def update_loading(current, total)
      if total.positive?
        playlist_progress.fraction = current.to_f / total
      end
    end

    def search=(search)
      playlist_searchbar.search_mode = search
      search
    end

    # --- Widgets ---------------------------------------------------------

    def root
      @root ||= Adwaita::ToolbarView.new.tap do |view|
        view.add_css_class("playlistview")
        view.add_css_class("playlist-background")
      end
    end

    def header_bar
      @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
        bar.show_title = true
      end
    end

    def search_button
      @search_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "system-search-symbolic"
        button.action_name = "queue.search"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Search Songs in the Playlist")
      end
    end

    def select_button
      @select_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "selection-mode-symbolic"
        button.action_name = "queue.select"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Select Songs in the Playlist")
      end
    end

    def back_button
      @back_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "go-previous-symbolic"
        button.action_name = "queue.toggle"
        button.valign = :center
        button.visible = false
        button.tooltip_text = I18n.i18n("Close the Playlist")
      end
    end

    def queue_length_box
      @queue_length_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.valign = :center
      end
    end

    def playlist_label
      @playlist_label ||= Gtk::Label.new(I18n.i18n("Playlist")).tap do |label|
        label.ellipsize = :end
        label.add_css_class("heading")
      end
    end

    def queue_length_label
      @queue_length_label ||= Gtk::Label.new.tap do |label|
        label.ellipsize = :end
        label.add_css_class("caption")
      end
    end

    def playlist_searchbar = @playlist_searchbar ||= Gtk::SearchBar.new

    def playlist_searchentry
      @playlist_searchentry ||= Gtk::SearchEntry.new.tap do |entry|
        entry.placeholder_text = I18n.i18n("Search songs")
        entry.hexpand = true
      end
    end

    def playlist_overlay = @playlist_overlay ||= Gtk::Overlay.new

    def playlist_progress
      @playlist_progress ||= Gtk::ProgressBar.new.tap do |progress|
        progress.valign = :start
        progress.hexpand = true
        progress.visible = false
        progress.add_css_class("osd")
      end
    end

    def scroller
      @scroller ||= Gtk::ScrolledWindow.new.tap do |window|
        window.hscrollbar_policy = :never
        window.vscrollbar_policy = :automatic
        window.propagate_natural_height = true
        window.vexpand = true
      end
    end

    def queue_view
      @queue_view ||= Gtk::ListView.new(nil, nil).tap do |view|
        view.single_click_activate = true
        view.add_css_class("navigation-sidebar")
      end
    end

    def queue_actionbar
      @queue_actionbar ||= Gtk::ActionBar.new.tap do |bar|
        bar.revealed = false
        bar.add_css_class("flat")
      end
    end

    def queue_select_all_button
      @queue_select_all_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "edit-select-all-symbolic"
        button.tooltip_text = I18n.i18n("Select All Songs")
      end
    end

    def queue_remove_button
      @queue_remove_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "app-remove-symbolic"
        button.tooltip_text = I18n.i18n("Remove Selected Songs")
      end
    end

    def queue_selected_label
      @queue_selected_label ||= Gtk::Label.new.tap do |label|
        label.add_css_class("caption")
      end
    end
  end
end
