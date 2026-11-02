# frozen_string_literal: true

require_relative "song"

module Amberol
  module Audio
    # The state the UI binds to: the current song's metadata, the playback
    # position, whether we are playing, and the volume.
    #
    # Ported from upstream's src/audio/state.rs. There it is a GObject whose
    # read-only properties the window binds widgets to; the Ruby bindings
    # cannot install properties on a subclass, so the same nine notifications
    # — playing, position, song, title, artist, album, duration, cover and
    # volume — are delivered to listeners registered with #on_notify, and the
    # window connects to those instead of to "notify::".
    class PlayerState
      PROPERTIES = %i[playing position song title artist album duration cover volume].freeze

      def initialize
        @playback_state = :stopped
        @position = 0
        @current_song = nil
        @volume = 1.0
        @listeners = {}
      end

      # Registers a listener for one property. The block is handed this state
      # object; the handle it returns can be passed to #disconnect, which is
      # what the window does when it closes.
      def on_notify(property, &block)
        (@listeners[property.to_sym] ||= []) << block
        [property.to_sym, block]
      end

      def disconnect(handle)
        handle.then do |(property, block)|
          @listeners.fetch(property, []).delete(block)
        end
      end

      def title = @current_song&.title
      def artist = @current_song&.artist
      def album = @current_song&.album
      def duration = @current_song&.duration || 0
      def cover = @current_song&.cover_texture

      def playing? = @playback_state == :playing

      def playback_state = @playback_state

      # Returns whether the state actually changed, the way upstream's
      # set_playback_state does.
      def playback_state=(state)
        state.to_sym.then do |value|
          @playback_state.then do |old_state|
            @playback_state = value
            unless old_state == value
              notify(:playing)
            end
            old_state != value
          end
        end
      end

      def current_song = @current_song

      def current_song=(song)
        @current_song = song
        @position = 0
        %i[song title artist album duration cover position].each { |property| notify(property) }
        song
      end

      def position = @position

      def position=(position)
        @position = position
        notify(:position)
        position
      end

      def volume = @volume

      # Only two digits of precision are notified, so a volume coming back
      # from the backend cannot start a notification cycle with the slider.
      def volume=(volume)
        @volume.then do |old_volume|
          @volume = volume
          unless format("%.2f", old_volume) == format("%.2f", volume)
            notify(:volume)
          end
        end
        volume
      end

      private

        def notify(property)
          @listeners.fetch(property.to_sym, []).each { |listener| listener.call(self) }
        end
    end
  end
end
