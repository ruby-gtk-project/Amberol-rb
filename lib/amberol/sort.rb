# frozen_string_literal: true

require "gtk4"
require_relative "search"
require_relative "utils"

module Amberol
  # The playlist's sorter.
  #
  # Ported from upstream's src/sort.rs, a Gtk::Sorter subclass with a "search"
  # property: while a search is running it orders the songs by their fuzzy
  # score, best first, and with no search it falls back to the file ordering
  # utils::cmp_two_files gives — which is the order the songs were queued in.
  #
  # The Ruby bindings cannot subclass Gtk::Sorter, and Gtk::CustomSorter is no
  # help either: its compare function is handed the two items as raw pointers
  # rather than as objects, so there is nothing to call #file or #search_key
  # on. The window therefore orders the model it keeps with #compare, which is
  # the same comparison upstream's sorter makes.
  class FuzzySorter
    def initialize
      @search = nil
    end

    def search = @search

    def search=(search)
      search.to_s.then do |needle|
        unless @search == needle
          @search = needle
        end
      end
      search
    end

    # Upstream reports SorterOrder::Partial, since two songs can tie.
    def order = :partial

    def compare(first, second)
      if @search.nil? || @search.empty?
        Utils.cmp_two_files(nil, first.file, second.file)
      else
        compare_scores(first, second)
      end
    end

    private

      # The better score sorts first, so the comparison is the reverse of the
      # scores'.
      def compare_scores(first, second)
        score(first).then do |first_score|
          score(second).then do |second_score|
            second_score <=> first_score
          end
        end
      end

      def score(song) = FuzzyMatcher.score(song.search_key, @search) || -1
  end
end
