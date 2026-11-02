# frozen_string_literal: true

require "gtk4"
require_relative "cover_picture"

module Amberol
  # The cover art area above the song details.
  #
  # Ported from upstream's src/song_cover.rs and src/gtk/song-cover.blp: a
  # stack holding the "folder-music-symbolic" placeholder and the cover
  # picture, centred in the window.
  class SongCover
    def build
      root.tap do |box|
        box.append(cover_stack)

        cover_stack.tap do |stack|
          stack.add_named(placeholder_image, "no-image")
          stack.add_named(album_image, "cover-image")
          stack.visible_child_name = "no-image"
        end
      end
    end

    # Upstream's show_cover_image: the placeholder when there is no cover.
    def show_cover_image(has_image)
      if has_image
        cover_stack.visible_child_name = "cover-image"
      else
        cover_stack.visible_child_name = "no-image"
      end
    end

    def root
      @root ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.halign = :center
        box.valign = :center
        box.add_css_class("songcover")
      end
    end

    def cover_stack = @cover_stack ||= Gtk::Stack.new

    def album_image = @album_image ||= CoverPicture.new(:large)

    def placeholder_image
      @placeholder_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = "folder-music-symbolic"
        image.pixel_size = 64
        image.overflow = :hidden
        image.add_css_class("card")
        image.add_css_class("dim-label")
      end
    end
  end
end
