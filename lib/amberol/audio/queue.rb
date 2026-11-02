# frozen_string_literal: true

require "gtk4"
require_relative "cover_cache"
require_relative "shuffle_list_model"
require_relative "song"

module Amberol
  module Audio
    # The playlist.
    #
    # Ported from upstream's src/audio/queue.rs: the songs, the shuffled view
    # over them, the repeat mode, and the position of the current song.
    #
    # Upstream keeps the songs in a Gio::ListStore and reads them back out of
    # it. The port keeps them in a Ruby array instead, and the shuffled view
    # mirrors that array into the list store the playlist binds to: a song
    # read back out of a store it was just removed from can point at freed
    # memory, so the Ruby side holds the strong reference and the store only
    # drives the view.
    #
    # Upstream's three read-only properties — "current", "repeat-mode" and
    # "n-songs" — are notified to the listeners #on_notify registers, since
    # the Ruby bindings cannot install properties on a subclass.
    class Queue
      REPEAT_MODES = %i[consecutive repeat_all repeat_one].freeze

      def initialize
        @songs = []
        @shuffle = ShuffleListModel.new(self)
        @repeat_mode = :consecutive
        @current_pos = nil
        @shuffled = false
        @listeners = {}
      end

      # The model the playlist view binds to: the shuffled view, not the
      # songs in the order they were queued.
      def model = @shuffle.model

      def on_notify(property, &block)
        (@listeners[property.to_sym] ||= []) << block
        [property.to_sym, block]
      end

      def disconnect(handle)
        handle.then { |(property, block)| @listeners.fetch(property, []).delete(block) }
      end

      # The songs in the order they were queued; the shuffled view reads this.
      def songs = @songs.dup

      # The songs in the order they are shown, which is what the playlist
      # cache is written in.
      def visible_songs = @shuffle.songs

      def n_songs = @shuffle.n_items

      def empty? = @songs.empty?

      def song_at(position) = @shuffle.item(position)

      def current_song
        if @current_pos.nil?
          nil
        else
          song_at(@current_pos)
        end
      end

      def current_song_index = @current_pos

      def current_song=(song)
        if song.nil?
          @current_pos = nil
          notify(:current)
        else
          index = (0...n_songs).find { |position| song.equals?(song_at(position)) }
          unless index.nil?
            @current_pos = index
            notify(:current)
          end
        end
        song
      end

      # Upstream refuses the invalid placeholder song rather than queueing it.
      def add_song(song)
        if song.valid?
          @songs << song
          @shuffle.refresh
          notify(:n_songs)
          true
        else
          false
        end
      end

      def add_songs(songs)
        @songs.concat(songs)
        @shuffle.refresh
        notify(:n_songs)
      end

      def remove_song(song)
        was_shuffled = @shuffle.shuffled?
        n_before = n_songs

        @songs.index { |queued| queued.equals?(song) }.then do |position|
          unless position.nil?
            @songs.delete_at(position)
          end
        end

        @shuffle.refresh

        unless n_before == n_songs
          if was_shuffled
            @shuffle.reshuffle(0)
          end
          notify(:n_songs)
        end

        if empty?
          @current_pos = nil
        end
      end

      def clear
        CoverCache.global.clear
        @current_pos = nil
        @songs = []
        @shuffle.refresh
        notify(:n_songs)
      end

      def skip_song(position)
        @current_pos = position
        notify(:current)
        song_at(position)
      end

      def previous_song
        if @current_pos.nil? || @current_pos.zero?
          nil
        else
          @current_pos -= 1
          notify(:current)
          song_at(@current_pos)
        end
      end

      # The next song for the current repeat mode, or nil when the queue has
      # run out — which is what stops playback.
      def next_song
        if n_songs.zero?
          nil
        elsif @current_pos.nil?
          @current_pos = 0
          notify(:current)
          song_at(0)
        else
          advance
        end
      end

      def repeat_mode = @repeat_mode

      def repeat_mode=(mode)
        mode.to_sym.then do |value|
          unless @repeat_mode == value
            @repeat_mode = value
            notify(:repeat_mode)
          end
        end
        mode
      end

      # The next mode in upstream's rotation: consecutive, all, one.
      def toggle_repeat_mode
        REPEAT_MODES[(REPEAT_MODES.index(@repeat_mode) + 1) % REPEAT_MODES.length].then do |mode|
          self.repeat_mode = mode
          mode
        end
      end

      def first_song? = @current_pos == 0

      def last_song?
        if @current_pos.nil? || n_songs.zero?
          false
        else
          @current_pos == n_songs - 1
        end
      end

      def shuffled? = @shuffled

      def shuffled=(shuffled)
        unless @shuffled == shuffled
          @shuffled = shuffled
          if shuffled
            @shuffle.reshuffle(@current_pos || 0)
          else
            song = song_at(@current_pos || 0)
            @shuffle.unshuffle
            self.current_song = song
          end
        end
        shuffled
      end

      # Toggles one song's selection, the way a click in selection mode does.
      def select_song_at(index)
        @shuffle.item(index).then do |song|
          unless song.nil?
            song.set_selected(!song.selected?)
          end
        end
      end

      def unselect_all_songs
        @songs.each { |song| song.set_selected(false) }
      end

      def n_selected_songs = @songs.count(&:selected?)

      def selected_songs = @songs.select(&:selected?)

      def contains?(song) = @songs.any? { |queued| queued.equals?(song) }

      private

        def advance
          n_songs.then do |count|
            next_position(count).then do |position|
              @current_pos = position
              notify(:current)
              if position.nil?
                nil
              else
                song_at(position)
              end
            end
          end
        end

        def next_position(count)
          case @repeat_mode
          when :repeat_one then @current_pos
          when :repeat_all then (@current_pos + 1) % count
          else
            if @current_pos < count - 1
              @current_pos + 1
            end
          end
        end

        def notify(property)
          @listeners.fetch(property.to_sym, []).each { |listener| listener.call(self) }
        end
    end
  end
end
