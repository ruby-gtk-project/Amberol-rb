# frozen_string_literal: true

require "gtk4"
require_relative "i18n"

module Amberol
  # The album cover.
  #
  # Ported from upstream's src/cover_picture.rs, a Gtk::Widget subclass whose
  # snapshot scales the cover texture to the widget, keeps its aspect ratio and
  # centres it, at one of two fixed sizes.
  #
  # The Ruby bindings cannot override a widget's snapshot or measure vfuncs, so
  # the port subclasses Gtk::Picture — which draws a paintable scaled, centred
  # and aspect-correct — and fixes the size the same way. The CSS name is
  # "picture" either way, and the widget wears the same "cover" class.
  class CoverPicture < Gtk::Picture
    type_register

    LARGE_SIZE = 192
    SMALL_SIZE = 48

    SIZES = {large: LARGE_SIZE, small: SMALL_SIZE}.freeze

    def initialize(cover_size = :large)
      super()
      @cover_size = cover_size
      add_css_class("cover")
      self.overflow = :hidden
      self.content_fit = :contain
      self.can_shrink = true
      self.accessible_role = :img
      apply_size
    end

    def cover = paintable

    def cover=(texture)
      self.paintable = texture
      texture
    end

    def cover_size = @cover_size

    def cover_size=(cover_size)
      @cover_size = cover_size.to_sym
      apply_size
      cover_size
    end

    private

      def apply_size
        SIZES.fetch(@cover_size, LARGE_SIZE).then do |size|
          set_size_request(size, size)
        end
      end
  end
end
