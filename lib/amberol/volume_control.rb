# frozen_string_literal: true

require "gtk4"

module Amberol
  # The volume slider.
  #
  # Ported from upstream's src/volume_control.rs and src/gtk/volume-control.blp:
  # a mute button, a 0..1 scale with a 0.05 step, and a loud-speaker icon, plus
  # the scroll controller that moves the slider by one step per notch.
  #
  # Upstream's "volume-changed" signal is a Ruby callback here, registered with
  # #on_volume_changed; its "toggle-mute" property is driven by the
  # "volume.toggle-mute" action the mute button activates, in the action group
  # #action_group builds.
  class VolumeControl
    STEP = 0.05

    def initialize
      @toggle_mute = false
      @prev_volume = 1.0
      @listeners = []
    end

    def build
      root.tap do |box|
        box.append(volume_low_button)
        box.append(volume_scale)
        box.append(volume_high_image)

        volume_scale.tap do |scale|
          scale.adjustment = adjustment
          scale.add_controller(scroll_controller)
        end

        adjustment.signal_connect("notify::value") { on_value_changed }

        box.insert_action_group("volume", action_group)
      end
    end

    # The volume the slider is showing, on the cubic scale the player expects.
    def volume = adjustment.value

    def volume=(volume)
      adjustment.value = volume.clamp(0.0, 1.0)
      volume
    end

    def muted? = @toggle_mute

    # Registers a listener for upstream's "volume-changed" signal.
    def on_volume_changed(&block)
      @listeners << block
      block
    end

    def root
      @root ||= Gtk::Box.new(:horizontal, 0).tap do |box|
        box.add_css_class("volume")
        box.hexpand = true
      end
    end

    def volume_low_button
      @volume_low_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "audio-volume-low-symbolic"
        button.action_name = "volume.toggle-mute"
        button.valign = :center
        button.add_css_class("flat")
        button.add_css_class("circular")
      end
    end

    def volume_scale
      @volume_scale ||= Gtk::Scale.new(:horizontal, nil).tap do |scale|
        scale.hexpand = true
        scale.margin_end = 6
        scale.draw_value = false
      end
    end

    def volume_high_image
      @volume_high_image ||= Gtk::Image.new.tap do |image|
        image.icon_name = "audio-volume-high-symbolic"
        image.margin_end = 10
      end
    end

    def adjustment
      @adjustment ||= Gtk::Adjustment.new(
        1.0,
        0.0,
        1.0,
        STEP,
        STEP,
        0.0,
      )
    end

    # Upstream installs "volume.toggle-mute" as a property action on the
    # widget class, so the mute button can carry an action name rather than a
    # handler; the group lives on the root widget here, and its children
    # inherit it.
    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(toggle_mute_action)
      end
    end

    def toggle_mute_action
      @toggle_mute_action ||= Gio::SimpleAction.new("toggle-mute", nil, GLib::Variant.new(false)).tap do |action|
        action.signal_connect("activate") do |simple_action, _parameter|
          (!simple_action.state).then do |muted|
            simple_action.state = GLib::Variant.new(muted)
            toggle_mute(muted)
          end
        end
      end
    end

    # Scrolling over the slider moves it by one step, and stops the event
    # there so the scroll does not also move whatever is underneath.
    def scroll_controller
      @scroll_controller ||= Gtk::EventControllerScroll.new(:vertical).tap do |controller|
        controller.name = "volume-scroll"
        controller.signal_connect("scroll") do |_controller, _dx, dy|
          adjustment.value = (adjustment.value - (dy * adjustment.step_increment))
            .clamp(adjustment.lower, adjustment.upper)
          true
        end
      end
    end

    private

      # Mutes by remembering the volume and sliding to zero, and unmutes by
      # sliding back to the volume it remembered.
      def toggle_mute(muted)
        unless @toggle_mute == muted
          @toggle_mute = muted
          if muted
            @prev_volume = adjustment.value
            adjustment.value = 0.0
          else
            adjustment.value = @prev_volume
          end
        end
      end

      def on_value_changed
        adjustment.value.then do |value|
          if value == adjustment.lower
            volume_low_button.icon_name = "audio-volume-muted-symbolic"
          else
            volume_low_button.icon_name = "audio-volume-low-symbolic"
          end
          @listeners.each { |listener| listener.call(value) }
        end
      end
  end
end
