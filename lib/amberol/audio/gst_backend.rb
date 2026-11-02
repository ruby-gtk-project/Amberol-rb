# frozen_string_literal: true

require "gtk4"

module Amberol
  module Audio
    # The playback backend.
    #
    # Ported from upstream's src/audio/gst_backend.rs, which wraps GstPlay and
    # posts playback actions back to the player over a channel. GTK4's own
    # media backend *is* a GstPlay wrapper, and the Ruby bindings expose it as
    # Gtk::MediaFile, so that is what plays the audio here: the same set of
    # operations (set a uri, play, pause, stop, seek, set the volume) and the
    # same four actions posted back — PlayNext at end of stream, UpdatePosition
    # while playing, UpdatePosition after a seek, and VolumeChanged.
    #
    # `sender` is the proc the player hands over; it takes an action name and
    # its arguments, exactly as upstream's glib::Sender takes a PlaybackAction.
    class GstBackend
      # Upstream configures GstPlay with a 250ms position update interval.
      POSITION_UPDATE_INTERVAL = 250

      # Gtk::MediaStream works in microseconds; the app in whole seconds.
      USECS_PER_SEC = 1_000_000

      def initialize(sender)
        @sender = sender
        @replaygain = :off
        @position_source = nil
        @file = nil
        connect_signals
      end

      # The GFile handed to the media stream is kept in @file: GStreamer's
      # streaming thread touches it long after this call returns, and a Ruby
      # wrapper that falls out of scope takes the GObject's last reference
      # with it, which crashes that thread rather than this one.
      def set_song_uri(uri)
        if uri.nil?
          @file = nil
          media.clear
        else
          @file = Gio::File.new_for_uri(uri)
          media.file = @file
        end
      end

      def play
        media.play
        start_position_updates
      end

      def pause
        media.pause
        stop_position_updates
      end

      def stop
        media.playing = false
        media.seek(0)
        stop_position_updates
      end

      # Seeks `offset` seconds from `position`, clamped to the song, in the
      # direction asked for — upstream's GstBackend::seek.
      def seek(position, duration, offset, direction)
        destination(
          position,
          duration,
          offset,
          direction,
        ).then do |target|
          unless target.nil?
            seek_position(target)
          end
        end
      end

      def seek_position(position)
        if media.seekable?
          media.seek(position * USECS_PER_SEC)
          send_position(position, true)
        end
      end

      def seek_start = seek_position(0)

      # The UI works in the cubic volume scale a slider wants; GStreamer (and
      # Gtk::MediaStream with it) works in the linear one.
      def set_volume(volume)
        media.volume = cubic_to_linear(volume)
      end

      def volume = linear_to_cubic(media.volume)

      # Upstream builds an rgvolume/rglimiter filter bin and installs it as
      # the playbin's audio-filter; GTK's media backend exposes no hook to
      # install one on, so the mode is recorded and `replaygain_available?` is
      # false — the state upstream is in whenever the ReplayGain elements are
      # missing, which disables the window's win.replaygain action.
      def set_replaygain(mode)
        @replaygain = mode
      end

      def replaygain = @replaygain

      def replaygain_available? = false

      private

        def media = @media ||= Gtk::MediaFile.new

        def connect_signals
          media.signal_connect("notify::ended") do |stream, _param|
            if stream.ended?
              stop_position_updates
              @sender.call(:play_next)
            end
          end

          media.signal_connect("notify::error") do |stream, _param|
            unless stream.error.nil?
              warn("GStreamer error: #{stream.error.message}")
            end
          end

          media.signal_connect("notify::volume") do |stream, _param|
            @sender.call(:volume_changed, linear_to_cubic(stream.volume))
          end
        end

        def start_position_updates
          if @position_source.nil?
            @position_source = GLib::Timeout.add(POSITION_UPDATE_INTERVAL) do
              send_position(media.timestamp / USECS_PER_SEC, false)
              true
            end
          end
        end

        def stop_position_updates
          unless @position_source.nil?
            GLib::Source.remove(@position_source)
            @position_source = nil
          end
        end

        def send_position(position, notify)
          @sender.call(:update_position, position, notify)
        end

        def destination(position, duration, offset, direction)
          case direction
          when :backwards then [position - offset, 0].max
          else
            if duration.zero?
              nil
            else
              [position + offset, duration].min
            end
          end
        end

        def cubic_to_linear(volume) = volume.clamp(0.0, 1.0)**3

        def linear_to_cubic(volume) = volume.clamp(0.0, 1.0)**(1.0 / 3.0)
    end
  end
end
