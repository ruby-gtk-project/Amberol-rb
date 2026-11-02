# frozen_string_literal: true

module Amberol
  module Audio
    # The interface the player drives its external integrations through.
    #
    # Ported from upstream's src/audio/controller.rs, a four-method trait. In
    # Ruby it is a module controllers include: the default implementations do
    # nothing, so a controller overrides only the notifications it cares
    # about — which is what upstream's controllers do with empty trait
    # methods.
    module Controller
      def set_playback_state(_state) = nil

      def set_song(_song) = nil

      def set_position(_position, _notify) = nil

      def set_repeat_mode(_mode) = nil
    end
  end
end
