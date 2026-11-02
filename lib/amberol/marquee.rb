# frozen_string_literal: true

require "adwaita"

module Amberol
  # A label that scrolls its text when the text is wider than the space it has.
  #
  # Ported from upstream's src/marquee.rs, a Gtk::Widget subclass that lays out
  # a child label, measures it against the allocation, and — when it does not
  # fit — snapshots the label twice behind a gradient mask while an
  # Adw.TimedAnimation drives the offset.
  #
  # The Ruby bindings cannot override measure, size_allocate or snapshot, so
  # the port scrolls a label inside a Gtk::ScrolledWindow instead: the same
  # Adw.TimedAnimation drives the horizontal adjustment, with the same 30ms per
  # pixel pace and the same 1.5s rest at each end, and the scrolled window
  # clips the overflow the mask used to hide.
  class Marquee < Gtk::ScrolledWindow
    type_register

    # Upstream's animation pace: 30ms per pixel of label width.
    MS_PER_PIXEL = 30

    # How long the text rests before it starts moving again.
    REST_MS = 1500

    def initialize(width_chars: 20, css_class: nil)
      super()
      @width_chars = width_chars
      self.hscrollbar_policy = :external
      self.vscrollbar_policy = :never
      self.propagate_natural_width = false
      self.propagate_natural_height = true
      self.accessible_role = :label
      self.child = label
      label.width_chars = width_chars
      unless css_class.nil?
        label.add_css_class(css_class)
      end
      hadjustment.signal_connect("changed") { update_animation }
      label.signal_connect("notify::label") { update_animation }
    end

    def label_text = label.label

    # Upstream's "label" property: setting it restarts the animation, so the
    # new text is read from the beginning.
    def label_text=(text)
      label.label = text.to_s
      hadjustment.value = hadjustment.lower
      update_animation
      text
    end

    def width_chars = @width_chars

    def width_chars=(width_chars)
      @width_chars = width_chars
      label.width_chars = width_chars
      width_chars
    end

    def label
      @label ||= Gtk::Label.new.tap do |widget|
        widget.xalign = 0.5
        widget.single_line_mode = true
        widget.ellipsize = :none
      end
    end

    private

      def overflow_width
        [hadjustment.upper - hadjustment.page_size, 0.0].max
      end

      # Starts the scroll when the text overflows and stops it when it fits,
      # which is what upstream does from size_allocate.
      def update_animation
        overflow_width.then do |overflow|
          if overflow.positive?
            animation.value_to = overflow
            animation.duration = [overflow.to_i * MS_PER_PIXEL, REST_MS].max
            unless animation.state == Adwaita::AnimationState::PLAYING
              animation.play
            end
          else
            animation.pause
            hadjustment.value = hadjustment.lower
          end
        end
      end

      # An alternating animation that never ends: the text scrolls to the far
      # edge, then back, for as long as it does not fit.
      def animation
        @animation ||= Adwaita::TimedAnimation.new(
          self,
          0.0,
          1.0,
          REST_MS,
          animation_target,
        ).tap do |timed|
          timed.easing = Adwaita::Easing::EASE_IN_OUT_CUBIC
          timed.alternate = true
          timed.repeat_count = 0
        end
      end

      def animation_target
        @animation_target ||= Adwaita::CallbackAnimationTarget.new do |value|
          hadjustment.value = value
        end
      end
  end
end
