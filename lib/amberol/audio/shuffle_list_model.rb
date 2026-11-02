# frozen_string_literal: true

require "gtk4"
require_relative "song"

module Amberol
  module Audio
    # A shuffled view of the queue's songs.
    #
    # Ported from upstream's src/audio/shuffle.rs, where it is a GListModel
    # implementation that maps a position through a permutation vector before
    # asking the wrapped model for an item.
    #
    # The Ruby bindings cannot implement the GListModel interface, so the
    # mapping is materialised twice over: in a Ruby array, which is what every
    # read goes through, and in a Gio::ListStore, which is what the playlist's
    # ListView binds to. Keeping the array is not just convenience — a song
    # read back out of a list store it has just been removed from can point at
    # freed memory and take the process down with it, so the Ruby side holds a
    # strong reference to every live song and the store only ever drives the
    # view.
    class ShuffleListModel
      def initialize(source)
        @source = source
        @store = Gio::ListStore.new(Song)
        @ordered = []
        @shuffle = nil
        refresh
      end

      # The model the view binds to.
      def model = @store

      def n_items = @ordered.length

      def item(position)
        if position.nil? || position.negative? || position >= @ordered.length
          nil
        else
          @ordered[position]
        end
      end

      def songs = @ordered.dup

      def shuffled? = !@shuffle.nil?

      # Shuffles every song except the one at `anchor`, which keeps its
      # position so the song playing now does not jump.
      def reshuffle(anchor)
        @source.songs.length.then do |count|
          if count.zero?
            @shuffle = nil
          else
            @shuffle = permutation(count, anchor)
          end
          refresh
        end
      end

      def unshuffle
        @shuffle = nil
        refresh
      end

      # Rebuilds the order from the source's songs, and hands the new order to
      # the store the view watches.
      def refresh
        reconcile
        @ordered = ordered_songs
        @store.remove_all
        unless @ordered.empty?
          @store.splice(0, 0, @ordered)
        end
        @ordered
      end

      private

        def permutation(count, anchor)
          [anchor.to_i, count - 1].min.then do |fixed|
            before = (0...fixed).to_a
            after = ((fixed + 1)...count).to_a.shuffle
            before.shuffle + [fixed] + after
          end
        end

        # A song added or removed while shuffled leaves the permutation stale,
        # so positions that no longer exist drop out and songs it does not
        # mention are shuffled in at the end.
        def reconcile
          @source.songs.length.then do |count|
            unless @shuffle.nil? || @shuffle.length == count
              kept = @shuffle.select { |index| index < count }
              @shuffle = kept + ((0...count).to_a - kept).shuffle
            end
          end
        end

        def ordered_songs
          @source.songs.then do |songs|
            if @shuffle.nil?
              songs
            else
              @shuffle.filter_map { |index| songs[index] }
            end
          end
        end
    end
  end
end
