# frozen_string_literal: true

require "gstreamer"
require "gstreamer_play"

module Amberol
  module Audio
    # Builds the rgvolume/rglimiter ReplayGain filter bin and installs it on
    # (or clears it from) a playbin's `audio-filter` property.
    #
    # Ported from upstream's `GstReplayGain` in src/audio/gst_backend.rs: a
    # small bin wrapping `rgvolume` linked into `rglimiter`, with ghost pads
    # standing in for the bin's own sink/src, so it can be handed to a
    # playbin as a single element.
    class ReplayGainFilter
      def self.build
        rg_volume = Gst::ElementFactory.make("rgvolume", "rg volume")
        rg_limiter = Gst::ElementFactory.make("rglimiter", "rg limiter")
        if rg_volume.nil? || rg_limiter.nil?
          nil
        else
          new(rg_volume, rg_limiter)
        end
      end

      def initialize(rg_volume, rg_limiter)
        @rg_volume = rg_volume
        @bin = Gst::Bin.new("filter bin").tap do |bin|
          bin.add(rg_volume)
          bin.add(rg_limiter)
          rg_volume.link(rg_limiter)
          bin.add_pad(ghost_pad("src", rg_limiter.get_static_pad("src")))
          bin.add_pad(ghost_pad("sink", rg_volume.get_static_pad("sink")))
        end
      end

      # Installs the bin as `pipeline`'s audio-filter in `album_mode` or
      # `track` mode, or clears the filter entirely for `:off` — upstream's
      # `GstReplayGain#set_mode`.
      def apply(pipeline, mode)
        case mode
        when :album then enable(pipeline, album_mode: true)
        when :track then enable(pipeline, album_mode: false)
        else pipeline.set_property("audio-filter", nil)
        end
      end

      private

        def enable(pipeline, album_mode:)
          @rg_volume.set_property("album-mode", album_mode)
          pipeline.set_property("audio-filter", @bin)
        end

        def ghost_pad(name, target)
          target.active = true
          Gst::GhostPad.new(name, target)
        end
    end

    # The playback backend.
    #
    # Ported from upstream's src/audio/gst_backend.rs: drives playback
    # through `gst_play::Play` directly (the `gstreamer_play` gem's
    # `GstPlay::Play`), the same way upstream does, with the same
    # rgvolume/rglimiter ReplayGain filter bin installed as the playbin's
    # `audio-filter`.
    #
    # GstPlay posts every event — errors, warnings, end-of-stream, position
    # updates, seek completion, volume changes — as messages on its own
    # `message_bus`, a plain `Gst::Bus`; {#watch_bus} watches it the same way
    # {WaveformGenerator} watches its own analysis pipeline's bus, and turns
    # each into the matching PlaybackAction.
    #
    # `sender` is the proc the player hands over; it takes an action name and
    # its arguments, exactly as upstream's glib::Sender takes a
    # PlaybackAction.
    class GstBackend
      # Upstream configures GstPlay with a 250ms position update interval.
      POSITION_UPDATE_INTERVAL = 250

      def initialize(sender)
        @sender = sender
        @replaygain = :off
        @replaygain_filter = ReplayGainFilter.build
        configure_player
        watch_bus
      end

      # `GstPlay::Play#uri=` with a real `nil` segfaults the Ruby binding
      # (confirmed directly, outside this app too — setting the URI string
      # property to NULL crashes inside the introspection marshaling, not
      # inside libgstplay itself). An empty string clears playback the same
      # way upstream's `set_uri(None)` does, without that crash; `#stop`
      # first so nothing is still streaming against the uri being cleared.
      def set_song_uri(uri)
        if uri.nil?
          gst_player.stop
          gst_player.set_uri("")
        else
          gst_player.uri = uri
        end
      end

      def play = gst_player.play

      def pause = gst_player.pause

      def stop = gst_player.stop

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

      def seek_position(position) = gst_player.seek(position * Gst::SECOND)

      def seek_start = seek_position(0)

      # The UI works in the cubic volume scale a slider wants; GStreamer (and
      # `GstPlay::Play`) works in the linear one.
      def set_volume(volume) = gst_player.set_volume(cubic_to_linear(volume))

      def volume = linear_to_cubic(gst_player.volume)

      # Upstream builds an rgvolume/rglimiter filter bin via `gst_play::Play`'s
      # own playbin and installs it as the pipeline's audio-filter —
      # {ReplayGainFilter} above does the same thing here. When this build's
      # gst-plugins-bad has no `rgvolume`/`rglimiter` elements,
      # {ReplayGainFilter.build} returns nil and #replaygain_available? is
      # false, matching upstream's own behaviour whenever those elements are
      # missing.
      def set_replaygain(mode)
        @replaygain = mode
        @replaygain_filter&.apply(gst_player.pipeline, mode)
      end

      def replaygain = @replaygain

      def replaygain_available? = !@replaygain_filter.nil?

      private

        def gst_player = @gst_player ||= GstPlay::Play.new

        def configure_player
          gst_player.set_video_track_enabled(false)
          gst_player.set_config(
            gst_player.config.tap do |config|
              config.set_value(
                "position-update-interval",
                GLib::Value.new(GLib::Type::UINT, POSITION_UPDATE_INTERVAL),
              )
            end,
          )
        end

        def watch_bus
          gst_player.message_bus.add_watch do |_bus, message|
            handle_message(message)
            true
          end
        end

        def handle_message(message)
          case message.structure["play-message-type"].value
          when GstPlay::PlayMessage::ERROR then handle_error(message)
          when GstPlay::PlayMessage::WARNING then handle_warning(message)
          when GstPlay::PlayMessage::END_OF_STREAM then @sender.call(:play_next)
          when GstPlay::PlayMessage::POSITION_UPDATED then handle_position_updated(message)
          when GstPlay::PlayMessage::SEEK_DONE then handle_seek_done(message)
          when GstPlay::PlayMessage::VOLUME_CHANGED then handle_volume_changed(message)
          end
        end

        def handle_error(message)
          GstPlay::PlayMessage.parse_error(message).then do |error, _debug|
            warn("GStreamer error: #{error.message}")
          end
        end

        def handle_warning(message)
          GstPlay::PlayMessage.parse_warning(message).then do |error, _debug|
            warn("GStreamer warning: #{error.message}")
          end
        end

        def handle_position_updated(message)
          GstPlay::PlayMessage.parse_position_updated(message).then do |position|
            send_position(position / Gst::SECOND, false)
          end
        end

        def handle_seek_done(message)
          GstPlay::PlayMessage.parse_seek_done(message).then do |position|
            send_position(position / Gst::SECOND, true)
          end
        end

        def handle_volume_changed(message)
          @sender.call(:volume_changed, linear_to_cubic(GstPlay::PlayMessage.parse_volume_changed(message)))
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
