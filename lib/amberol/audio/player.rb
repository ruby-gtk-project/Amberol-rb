# frozen_string_literal: true

require_relative "cover_cache"
require_relative "gst_backend"
require_relative "inhibit_controller"
require_relative "mpris_controller"
require_relative "player_state"
require_relative "queue"
require_relative "waveform_generator"

module Amberol
  module Audio
    # The object that owns playback.
    #
    # Ported from upstream's src/audio/player.rs: it holds the backend, the
    # queue, the state the UI binds to and the controllers, and it is the only
    # thing that moves between songs.
    #
    # Upstream's AudioPlayer and its controllers talk over a channel of
    # PlaybackAction values, because GStreamer can call back from another
    # thread. Gtk::MediaFile delivers its notifications on the main context,
    # so the channel is a plain proc here — #process_action still takes the
    # same actions under the same names, and `app_sender` still carries the
    # Raise action to the application.
    class AudioPlayer
      SEEK_STEP = 10

      # How far into a song "previous" restarts it rather than skipping back.
      SKIP_PREVIOUS_THRESHOLD = 10

      attr_reader :queue, :state, :waveform_generator

      def initialize(app_sender)
        @app_sender = app_sender
        @queue = Queue.new
        @state = PlayerState.new
        @backend = GstBackend.new(method(:process_action))
        @waveform_generator = WaveformGenerator.new
        @controllers = [
          InhibitController.new,
          @waveform_generator,
          MprisController.new(method(:process_action)),
        ]
      end

      # Upstream's AudioPlayer::process_action, reachable from the backend and
      # from the controllers.
      def process_action(action, *args)
        case action
        when :play then set_playback_state(:playing)
        when :pause then set_playback_state(:paused)
        when :stop then set_playback_state(:stopped)
        when :skip_previous then skip_previous
        when :skip_next then skip_next
        when :play_next then play_next
        when :update_position then update_position(args[0], args[1])
        when :volume_changed then update_volume(args[0])
        when :repeat then update_repeat_mode(args[0])
        when :seek then seek_offset(args[0])
        when :raise then present
        end
      end

      def toggle_play
        unless @queue.empty?
          if @state.playing?
            set_playback_state(:paused)
          else
            set_playback_state(:playing)
          end
        end
      end

      def play
        unless @state.playing?
          set_playback_state(:playing)
        end
      end

      def pause
        if @state.playing?
          set_playback_state(:paused)
        end
      end

      def stop = set_playback_state(:stopped)

      # Restarts the current song when we are more than a seek step into it,
      # and skips to the previous one otherwise.
      def skip_previous
        unless @queue.empty? || restart_current_song?
          @state.current_song&.set_playing(false)
          @queue.previous_song.then do |song|
            unless song.nil?
              switch_to(song)
            end
          end
        end
      end

      def skip_next
        unless @queue.empty?
          @state.current_song&.set_playing(false)
          @queue.next_song.then do |song|
            if song.nil?
              skip_to(0)
              set_playback_state(:stopped)
            else
              switch_to(song)
            end
          end
        end
      end

      def skip_to(position)
        unless @queue.empty? || @queue.current_song_index == position
          @state.current_song&.set_playing(false)
          @queue.skip_song(position).then do |song|
            if song.nil?
              @backend.set_song_uri(nil)
              @state.current_song = nil
              set_playback_state(:stopped)
            else
              switch_to(song)
            end
          end
        end
      end

      def seek_start
        (@state.position + 1).then do |position|
          @backend.seek(
            position,
            @state.duration,
            position,
            :backwards,
          )
        end
      end

      def seek_backwards = seek(SEEK_STEP, :backwards)

      def seek_forward = seek(SEEK_STEP, :forward)

      def seek_offset(offset)
        if offset.negative?
          seek(offset.abs, :backwards)
        else
          seek(offset.abs, :forward)
        end
      end

      # Seeks to a fraction of the song, which is what dragging the waveform
      # does.
      def seek_position_rel(position)
        @state.duration.to_f.then do |duration|
          @backend.seek_position((duration * position).clamp(0.0, duration).to_i)
        end
      end

      def seek_position_abs(position)
        @backend.seek_position([position, @state.duration].max)
      end

      def current_song=(song)
        @state.current_song = song
      end

      def set_volume(volume) = @backend.set_volume(volume)

      def toggle_repeat_mode
        @queue.toggle_repeat_mode.then do |mode|
          @controllers.each { |controller| controller.set_repeat_mode(mode) }
          mode
        end
      end

      def clear_queue
        stop
        @state.current_song = nil
        @queue.clear
        CoverCache.global.clear
      end

      def remove_song(song)
        if song.playing?
          skip_next
        end

        @queue.remove_song(song)

        if @queue.empty?
          @state.current_song = nil
        end
      end

      def set_replaygain(mode) = @backend.set_replaygain(mode)

      def replaygain_available? = @backend.replaygain_available?

      private

        # Upstream's set_playback_state: with a current song it just changes
        # state; with none it takes the next song off the queue first, and
        # stops when the queue has run out.
        def set_playback_state(state)
          if @state.current_song.nil?
            start_next_song(state)
          else
            apply_playback_state(state)
          end
        end

        def start_next_song(state)
          @queue.next_song.then do |song|
            if song.nil?
              @backend.set_song_uri(nil)
              @state.current_song = nil
              apply_playback_state(:stopped)
            else
              @controllers.each { |controller| controller.set_song(song) }
              song.set_playing(true)
              @backend.set_song_uri(song.uri)
              @state.current_song = song
              apply_playback_state(state)
            end
          end
        end

        def apply_playback_state(state)
          @state.playback_state = state
          @controllers.each { |controller| controller.set_playback_state(state) }

          case state
          when :playing then @backend.play
          when :paused then @backend.pause
          when :stopped then @backend.stop
          end
        end

        # Moves playback to `song`, keeping it paused across the switch when
        # it was paused before — upstream does the same so the backend never
        # plays a frame of the old song at the new position.
        def switch_to(song)
          @state.playing?.then do |was_playing|
            if was_playing
              set_playback_state(:paused)
            end

            @controllers.each { |controller| controller.set_song(song) }

            @backend.set_song_uri(song.uri)
            @backend.seek_start
            song.set_playing(true)
            @state.current_song = song

            if was_playing
              set_playback_state(:playing)
            end
          end
        end

        def restart_current_song?
          @state.current_song.then do |song|
            if song.nil?
              false
            elsif @state.position >= SKIP_PREVIOUS_THRESHOLD
              @backend.seek_start
              true
            else
              @queue.first_song?
            end
          end
        end

        def play_next = skip_next

        def seek(offset, direction)
          @backend.seek(
            @state.position,
            @state.duration,
            offset,
            direction,
          )
        end

        def update_position(position, notify)
          @state.position = position
          @controllers.each { |controller| controller.set_position(position, notify) }
        end

        def update_volume(volume)
          @state.volume = volume
        end

        def update_repeat_mode(mode)
          unless mode == @queue.repeat_mode
            @queue.repeat_mode = mode
            @controllers.each { |controller| controller.set_repeat_mode(mode) }
          end
        end

        def present = @app_sender.call(:present)
    end
  end
end
