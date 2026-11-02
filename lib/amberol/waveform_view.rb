# frozen_string_literal: true

require "adwaita"
require "gtk4"

module Amberol
  # The seek bar: the song's waveform, filled in up to the playback position.
  #
  # Ported from upstream's src/waveform_view.rs. There it is a Gtk::Widget
  # subclass that snapshots one two-pixel block per peak — fully coloured
  # behind the position, dimmed in front of it, half-lit under the pointer —
  # and emits "position-changed" when dragged, clicked or arrowed.
  #
  # The Ruby bindings cannot override snapshot, so the blocks are drawn with
  # Cairo on a Gtk::DrawingArea instead; the geometry, the three opacities and
  # the gestures are the same. With no peaks set it draws upstream's flat line
  # of blocks, which is what a song whose waveform has not been generated
  # looks like.
  class WaveformView < Gtk::DrawingArea
    type_register

    BAR_SIZE = 2
    SPACE_SIZE = 2
    BLOCK_SIZE = BAR_SIZE + SPACE_SIZE

    DEFAULT_WIDTH = 256
    DEFAULT_HEIGHT = 48

    # Upstream's two dimming factors, and the ones it uses in high contrast.
    EMPTY_OPACITY = 0.2
    HOVER_OPACITY = 0.45
    HIGH_CONTRAST_EMPTY_OPACITY = 0.4
    HIGH_CONTRAST_HOVER_OPACITY = 0.7

    def initialize
      super()
      @position = 0.0
      @hover_position = nil
      @peaks = nil
      @listeners = []
      add_css_class("waveformview")
      self.focusable = true
      self.accessible_role = :slider
      set_content_width(DEFAULT_WIDTH)
      set_content_height(DEFAULT_HEIGHT)
      set_draw_func { |_area, context, width, height| draw(context, width, height) }
      setup_gestures
    end

    def position = @position

    def position=(position)
      @position = position.to_f.clamp(0.0, 1.0)
      queue_draw
      position
    end

    def peaks = @peaks

    # Takes the generator's [left, right] pairs and normalises them against
    # the loudest peak in each channel, as upstream's normalize_peaks does.
    def peaks=(peaks)
      if peaks.nil? || peaks.empty?
        @peaks = nil
      else
        @peaks = normalize(peaks)
      end
      queue_resize
      queue_draw
      peaks
    end

    # Registers a listener for upstream's "position-changed" signal.
    def on_position_changed(&block)
      @listeners << block
      block
    end

    private

      def normalize(peaks)
        peaks.map { |pair| Array(pair).first(2).map(&:to_f) }.then do |pairs|
          max_left = pairs.map(&:first).max
          max_right = pairs.map(&:last).max
          pairs.map do |(left, right)|
            [divide(left, max_left), divide(right, max_right)]
          end
        end
      end

      def divide(value, divisor)
        if divisor.nil? || divisor.zero?
          0.0
        else
          value / divisor
        end
      end

      def draw(context, width, height)
        if width.positive? && height.positive?
          colour = style_context.color
          if @peaks.nil?
            draw_flat_line(
              context,
              colour,
              width,
              height,
            )
          else
            draw_peaks(
              context,
              colour,
              width,
              height,
            )
          end
        end
      end

      # The "no waveform yet" state: a row of blocks down the middle.
      def draw_flat_line(context, colour, width, height)
        set_colour(context, colour, 1.0)
        offset = SPACE_SIZE
        while offset < width - SPACE_SIZE
          context.rectangle(
            offset,
            (height / 2.0) - 1.0,
            BAR_SIZE,
            2.0,
          )
          offset += BLOCK_SIZE
        end
        context.fill
      end

      def draw_peaks(context, colour, width, height)
        cursors(width).then do |(played_edge, hover_edge)|
          accumulate(width).each_with_index do |(left, right), index|
            (index * BLOCK_SIZE).then do |offset|
              set_colour(context, colour, block_opacity(offset, played_edge, hover_edge))
              block_rectangle(
                context,
                offset,
                left,
                right,
                height,
              )
              context.fill
            end
          end
        end
      end

      # The played edge, and the edge the pointer adds: hovering behind the
      # position dims the stretch between them, hovering in front half-lights
      # it, which is what upstream's two cursor positions do.
      def cursors(width)
        (@position * width).then do |played|
          if @hover_position.nil?
            [played, played]
          elsif @hover_position <= @position
            [@hover_position * width, played]
          else
            [played, @hover_position * width]
          end
        end
      end

      def block_opacity(offset, played_edge, hover_edge)
        if offset < played_edge
          1.0
        elsif offset < hover_edge
          hover_opacity
        else
          empty_opacity
        end
      end

      def block_rectangle(context, offset, left, right, height)
        (height / 2.0).then do |center|
          top = (center - (right * height)).clamp(0.0, center)
          size = ((right * height) + (left * height)).clamp(2.0, height.to_f)
          context.rectangle(
            offset,
            top,
            BAR_SIZE,
            size,
          )
        end
      end

      # Averages the peaks down to one pair per block, so a long song's
      # thousands of peaks still fit the 256 pixels the view is wide.
      def accumulate(width)
        @peaks.then do |peaks|
          n_blocks = [(width / BLOCK_SIZE).to_i, 1].max
          per_block = [(peaks.length.to_f / n_blocks).ceil, 1].max
          peaks.each_slice(per_block).map do |slice|
            [
              slice.sum { |(left, _right)| left } / slice.length / 2.0,
              slice.sum { |(_left, right)| right } / slice.length / 2.0,
            ]
          end
        end
      end

      def empty_opacity
        if high_contrast?
          HIGH_CONTRAST_EMPTY_OPACITY
        else
          EMPTY_OPACITY
        end
      end

      def hover_opacity
        if high_contrast?
          HIGH_CONTRAST_HOVER_OPACITY
        else
          HOVER_OPACITY
        end
      end

      def high_contrast? = Adwaita::StyleManager.default.high_contrast?

      def set_colour(context, colour, opacity)
        context.set_source_rgba(
          colour.red,
          colour.green,
          colour.blue,
          colour.alpha * opacity,
        )
      end

      def setup_gestures
        add_controller(drag_gesture)
        add_controller(motion_controller)
        add_controller(key_controller)
      end

      def drag_gesture
        @drag_gesture ||= Gtk::GestureDrag.new.tap do |gesture|
          gesture.name = "waveform-drag"
          gesture.button = 0
          gesture.signal_connect("drag-begin") do |drag, start_x, _start_y|
            grab_focus
            drag.state = :claimed
            seek_to_coord(start_x)
          end
          gesture.signal_connect("drag-update") do |drag, offset_x, _offset_y|
            grab_focus
            drag.state = :claimed
            drag.start_point.then do |(start_x, _start_y)|
              seek_to_coord(start_x.to_f + offset_x)
            end
          end
        end
      end

      def motion_controller
        @motion_controller ||= Gtk::EventControllerMotion.new.tap do |controller|
          controller.name = "waveform-motion"
          controller.signal_connect("motion") do |_controller, x, _y|
            @hover_position = x / [width, 1].max.to_f
            queue_draw
          end
          controller.signal_connect("leave") do
            @hover_position = nil
            queue_draw
          end
        end
      end

      # Left and right arrows move the position by 5%, which is upstream's
      # keyboard step.
      def key_controller
        @key_controller ||= Gtk::EventControllerKey.new.tap do |controller|
          controller.name = "waveform-key"
          controller.signal_connect("key-released") do |_controller, keyval, _keycode, _state|
            case keyval
            when Gdk::Keyval::KEY_Left then emit_position(@position - 0.05)
            when Gdk::Keyval::KEY_Right then emit_position(@position + 0.05)
            end
          end
        end
      end

      def seek_to_coord(coordinate)
        [width, 1].max.then do |allocated|
          if direction == Gtk::TextDirection::RTL
            emit_position(1.0 - (coordinate / allocated.to_f))
          else
            emit_position(coordinate / allocated.to_f)
          end
        end
      end

      def emit_position(position)
        @listeners.each { |listener| listener.call(position) }
      end
  end
end
