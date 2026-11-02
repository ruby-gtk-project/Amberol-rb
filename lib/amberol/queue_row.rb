# frozen_string_literal: true

require "gtk4"
require_relative "cover_picture"
require_relative "i18n"

module Amberol
  # One row of the playlist.
  #
  # Ported from upstream's src/queue_row.rs and src/gtk/queue-row.blp: a stack
  # with the ordinary row on one page — cover, title, artist and the
  # "currently playing" indicator — and the selection-mode row, which swaps
  # the cover for a check button, on the other.
  #
  # Upstream's seven properties are plain accessors here; the playlist's list
  # factory sets them when it binds a song to a row, and #selected_changed is
  # the callback its "selected" notification turns into.
  class QueueRow < Gtk::Box
    type_register

    # The handle the playlist's factory keeps for the song's change listener,
    # so it can be taken off again when the row is unbound.
    attr_accessor :listener

    def initialize
      # A Gtk::Box subclass takes no construct arguments through the Ruby
      # bindings' GObject hook, so the orientation is set as a property.
      super()
      self.orientation = :horizontal
      self.spacing = 0
      @song = nil
      @playing = false
      @selection_mode = false
      @selected_listeners = []
      add_css_class("queuerow")
      build
    end

    def build
      tap do |box|
        box.append(row_stack)

        row_stack.tap do |stack|
          stack.add_named(details_box, "song-details")
          stack.add_named(selection_box, "selection-mode")
          stack.visible_child_name = "song-details"
        end

        details_box.tap do |details|
          details.append(song_cover_stack)
          details.append(song_labels_box)
          details.append(song_playing_image)

          song_cover_stack.tap do |cover|
            cover.add_named(song_cover_placeholder, "no-cover")
            cover.add_named(song_cover_image, "cover")
            cover.visible_child_name = "no-cover"
          end

          song_labels_box.tap do |labels|
            labels.append(song_title_label)
            labels.append(song_artist_label)
          end
        end

        selection_box.tap do |selection|
          selection.append(selected_button)
          selection.append(selection_labels_box)
          selection.append(selection_playing_image)

          selection_labels_box.tap do |labels|
            labels.append(selection_title_label)
            labels.append(selection_artist_label)
          end
        end

        selected_button.signal_connect("notify::active") do |button, _param|
          @song&.set_selected(button.active?)
          @selected_listeners.each { |listener| listener.call(self) }
        end
      end
    end

    def song = @song

    def song=(song)
      @song = song
      song
    end

    def song_title=(title)
      song_title_label.text = title.to_s
      selection_title_label.text = title.to_s
      title
    end

    def song_artist=(artist)
      song_artist_label.text = artist.to_s
      selection_artist_label.text = artist.to_s
      artist
    end

    def song_cover=(texture)
      if texture.nil?
        song_cover_image.cover = nil
        song_cover_stack.visible_child_name = "no-cover"
      else
        song_cover_image.cover = texture
        song_cover_stack.visible_child_name = "cover"
      end
      texture
    end

    def playing? = @playing

    def playing=(playing)
      unless @playing == playing
        @playing = playing
        update_mode
      end
      playing
    end

    def selection_mode? = @selection_mode

    def selection_mode=(selection_mode)
      unless @selection_mode == selection_mode
        @selection_mode = selection_mode
        update_mode
      end
      selection_mode
    end

    def selected? = selected_button.active?

    def selected=(selected)
      unless selected_button.active? == selected
        selected_button.active = selected
      end
      selected
    end

    # Upstream notifies "selected" when the check button is toggled; the
    # playlist counts the selection from this.
    def on_selected_changed(&block)
      @selected_listeners << block
      block
    end

    def row_stack = @row_stack ||= Gtk::Stack.new

    def details_box
      @details_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.add_css_class("song-details")
      end
    end

    def selection_box
      @selection_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.add_css_class("song-details")
      end
    end

    def song_cover_stack = @song_cover_stack ||= Gtk::Stack.new

    def song_cover_placeholder
      @song_cover_placeholder ||= Gtk::Image.new.tap do |image|
        image.icon_name = "folder-music-symbolic"
        image.pixel_size = 32
        image.add_css_class("dim-label")
        image.add_css_class("card")
        image.add_css_class("small")
      end
    end

    def song_cover_image
      @song_cover_image ||= CoverPicture.new(:small).tap do |picture|
        picture.halign = :center
        picture.valign = :center
        picture.add_css_class("card")
      end
    end

    def song_labels_box = @song_labels_box ||= labels_box
    def selection_labels_box = @selection_labels_box ||= labels_box

    def song_title_label = @song_title_label ||= inscription("song-title")
    def song_artist_label = @song_artist_label ||= inscription("song-artist")
    def selection_title_label = @selection_title_label ||= inscription("song-title")
    def selection_artist_label = @selection_artist_label ||= inscription("song-artist")

    def song_playing_image = @song_playing_image ||= playing_image
    def selection_playing_image = @selection_playing_image ||= playing_image

    def selected_button
      @selected_button ||= Gtk::CheckButton.new.tap do |button|
        button.halign = :center
        button.valign = :center
        button.add_css_class("selection-mode")
      end
    end

    private

      def labels_box
        Gtk::Box.new(:vertical, 3).tap do |box|
          box.valign = :center
          box.hexpand = true
        end
      end

      def inscription(css_class)
        Gtk::Inscription.new(nil).tap do |widget|
          widget.xalign = 0
          widget.text_overflow = :ellipsize_end
          widget.add_css_class(css_class)
        end
      end

      def playing_image
        Gtk::Image.new.tap do |image|
          image.icon_name = "audio-only-symbolic"
          image.pixel_size = 16
          image.halign = :center
          image.valign = :center
          image.opacity = 0
        end
      end

      # The indicator lives on whichever page is showing, so it follows the
      # row into and out of selection mode.
      def update_mode
        opacity = 0.0
        if @playing
          opacity = 1.0
        end

        if @selection_mode
          row_stack.visible_child_name = "selection-mode"
          selection_playing_image.opacity = opacity
        else
          row_stack.visible_child_name = "song-details"
          song_playing_image.opacity = opacity
        end
      end
  end
end
