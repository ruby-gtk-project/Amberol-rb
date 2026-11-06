# frozen_string_literal: true

require_relative "audio/controller"
require_relative "audio/cover_cache"
require_relative "audio/gst_backend"
require_relative "audio/inhibit_controller"
require_relative "audio/mpris_controller"
require_relative "audio/player"
require_relative "audio/player_state"
require_relative "audio/queue"
require_relative "audio/shuffle_list_model"
require_relative "audio/song"
require_relative "audio/tag_reader"
require_relative "audio/waveform_generator"

module Amberol
  # Audio playback.
  #
  # Ported from upstream's src/audio/mod.rs, which both wires the module
  # together and documents the design:
  #
  #   AudioPlayer: the main object managing the audio playback
  #   ├── PlayerState: the state tracker the UI binds to
  #   ├── Queue: the playlist
  #   ├── GstBackend: the player wrapper
  #   ╰── controllers: external bits of code that interact with the state
  #
  # Upstream reaches for message passing because GStreamer calls back from
  # whichever thread it likes, and working around that through the type system
  # means wrappers like Rc and Fragile. The port keeps the shape — the backend
  # and the controllers post actions to the player, the player owns the state,
  # and the UI only ever reads the state — but every notification already
  # arrives on the main context, so the channel is a proc.
  #
  # The enum values upstream declares as Rust enums are Ruby symbols here, and
  # they are listed below so there is one place that spells them.
  module Audio
    # upstream: PlaybackState
    PLAYBACK_STATES = %i[stopped playing paused].freeze

    # upstream: RepeatMode, in the order toggling rotates through
    REPEAT_MODES = %i[consecutive repeat_all repeat_one].freeze

    # upstream: ReplayGainMode, with the integer values the settings enum uses
    REPLAY_GAIN_MODES = {album: 0, track: 1, off: 2}.freeze

    # upstream: SeekDirection
    SEEK_DIRECTIONS = %i[forward backwards].freeze

    # upstream: PlaybackAction, the actions the backend and the controllers
    # post back to the player
    PLAYBACK_ACTIONS = %i[
      play
      pause
      stop
      skip_previous
      skip_next
      update_position
      volume_changed
      repeat
      seek
      play_next
      raise
    ].freeze

    # The settings key stores the nick; the player and the menu work with the
    # symbol. These two convert between them.
    def self.replay_gain_mode(value)
      REPLAY_GAIN_MODES.key(value) || :off
    end

    def self.replay_gain_value(mode)
      REPLAY_GAIN_MODES.fetch(mode.to_sym, REPLAY_GAIN_MODES[:off])
    end
  end
end
