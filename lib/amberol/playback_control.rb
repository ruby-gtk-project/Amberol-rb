# frozen_string_literal: true

require "gtk4"
require_relative "i18n"
require_relative "primary_menu"
require_relative "volume_control"

module Amberol
  # The transport controls under the song details.
  #
  # Ported from upstream's src/playback_control.rs and
  # src/gtk/playback-control.blp: previous/play/next in a row, the volume
  # control beneath them, and a bottom row carrying the playlist and shuffle
  # toggles on one side and the repeat and primary-menu buttons on the other.
  class PlaybackControl
    # The icon and the tooltip each repeat mode wears, from upstream's
    # PlaybackControl::set_repeat_mode.
    REPEAT_MODES = {
      consecutive: ["media-playlist-consecutive-symbolic", "Do Not Repeat"],
      repeat_all:  ["media-playlist-repeat-symbolic", "Repeat All Songs"],
      repeat_one:  ["media-playlist-repeat-song-symbolic", "Repeat the Current Song"],
    }.freeze

    def build
      root.tap do |box|
        box.append(controls_box)
        box.append(volume_control.build)
        box.append(bottom_box)

        controls_box.tap do |controls|
          controls.append(previous_button)
          controls.append(play_button)
          controls.append(next_button)
        end

        bottom_box.tap do |center|
          center.start_widget = start_box
          center.end_widget = end_box

          start_box.tap do |start|
            start.append(playlist_button)
            start.append(shuffle_button)
          end

          end_box.tap do |ending|
            ending.append(repeat_button)
            ending.append(menu_button)
          end
        end
      end
    end

    def set_repeat_mode(repeat_mode)
      REPEAT_MODES.fetch(repeat_mode.to_sym, REPEAT_MODES[:consecutive]).then do |(icon, tooltip)|
        repeat_button.icon_name = icon
        repeat_button.tooltip_text = I18n.i18n(tooltip)
      end
    end

    def root
      @root ||= Gtk::Box.new(:vertical, 6).tap do |box|
        box.width_request = 256
        box.add_css_class("playbackcontrol")
      end
    end

    def controls_box
      @controls_box ||= Gtk::Box.new(:horizontal, 24).tap do |box|
        box.halign = :center
        box.hexpand = true
      end
    end

    def volume_control = @volume_control ||= VolumeControl.new

    def bottom_box = @bottom_box ||= Gtk::CenterBox.new

    def start_box
      @start_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.halign = :start
        box.margin_end = 18
      end
    end

    def end_box
      @end_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.halign = :end
        box.margin_start = 18
      end
    end

    def previous_button
      @previous_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "media-skip-backward-symbolic"
        button.action_name = "win.previous"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Play the Previous Song")
        button.add_css_class("circular")
      end
    end

    def play_button
      @play_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "media-playback-start-symbolic"
        button.action_name = "win.play"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Toggle Play")
        button.add_css_class("circular")
        button.add_css_class("large")
      end
    end

    def next_button
      @next_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "media-skip-forward-symbolic"
        button.action_name = "win.next"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Play the Next Song")
        button.add_css_class("circular")
      end
    end

    def playlist_button
      @playlist_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "view-queue-symbolic"
        button.action_name = "queue.toggle"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Toggle Playlist")
        button.add_css_class("circular")
      end
    end

    def shuffle_button
      @shuffle_button ||= Gtk::ToggleButton.new.tap do |button|
        button.icon_name = "media-playlist-shuffle-symbolic"
        button.action_name = "queue.shuffle"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Shuffle the Playlist")
        button.add_css_class("circular")
      end
    end

    def repeat_button
      @repeat_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "media-playlist-consecutive-symbolic"
        button.action_name = "queue.repeat-mode"
        button.valign = :center
        button.tooltip_text = I18n.i18n("Enable Repeat")
        button.add_css_class("circular")
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.menu_model = PrimaryMenu.build
        button.icon_name = "open-menu-symbolic"
        button.primary = true
        button.halign = :end
        button.valign = :center
        button.direction = :up
        button.tooltip_text = I18n.i18n("Main Menu")
        button.add_css_class("circular")
      end
    end
  end
end
