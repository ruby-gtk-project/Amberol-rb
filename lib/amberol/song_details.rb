# frozen_string_literal: true

require "gtk4"
require_relative "marquee"

module Amberol
  # The title, artist and album of the song playing.
  #
  # Ported from upstream's src/song_details.rs and src/gtk/song-details.blp:
  # three marquees in a column, 20 characters wide for the title and 25 for
  # the artist and the album.
  class SongDetails
    def build
      root.tap do |box|
        box.append(details_box)

        details_box.tap do |column|
          column.append(title_label)
          column.append(artist_label)
          column.append(album_label)
        end
      end
    end

    def root
      @root ||= Gtk::Box.new(:vertical, 12).tap do |box|
        box.add_css_class("songdetails")
      end
    end

    def details_box
      @details_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.valign = :center
        box.margin_start = 6
        box.margin_end = 6
      end
    end

    def title_label = @title_label ||= Marquee.new(width_chars: 20, css_class: "song-title")
    def artist_label = @artist_label ||= Marquee.new(width_chars: 25, css_class: "song-artist")
    def album_label = @album_label ||= Marquee.new(width_chars: 25, css_class: "song-album")
  end
end
