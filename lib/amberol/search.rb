# frozen_string_literal: true

require "gtk4"

module Amberol
  # Fuzzy string scoring.
  #
  # Upstream's src/search.rs and src/sort.rs both reach for the
  # `fuzzy_matcher` crate's Skim matcher; the port scores the same way here,
  # and the filter and the sorter share it.
  #
  # A query matches when its characters appear in the key in order. The score
  # rewards a run of consecutive characters and a match at the start of a
  # word, so "dsotm" scores higher against "Dark Side of the Moon" than a
  # scattered match does.
  module FuzzyMatcher
    BASE_SCORE = 16
    CONSECUTIVE_BONUS = 8
    WORD_START_BONUS = 8
    GAP_PENALTY = 1

    WORD_SEPARATORS = [" ", "-", "_", ".", "/", "(", ")", "[", "]"].freeze

    # Returns an Integer score, or nil when the query does not match at all.
    # An empty query matches everything with a score of 0, which is what the
    # crate does.
    def self.score(key, query)
      query.to_s.downcase.then do |needle|
        if needle.empty?
          0
        else
          match(key.to_s.downcase, needle)
        end
      end
    end

    def self.match?(key, query) = !score(key, query).nil?

    def self.match(haystack, needle)
      total = 0
      index = 0
      previous_match = nil

      needle.each_char do |character|
        found = haystack.index(character, index)
        if found.nil?
          total = nil
          break
        end

        total += BASE_SCORE
        total += character_bonus(haystack, found, previous_match)
        total -= gap_penalty(found, previous_match)
        previous_match = found
        index = found + 1
      end

      total
    end

    def self.character_bonus(haystack, found, previous_match)
      bonus = 0
      if previous_match == found - 1
        bonus += CONSECUTIVE_BONUS
      end
      if word_start?(haystack, found)
        bonus += WORD_START_BONUS
      end
      bonus
    end

    def self.gap_penalty(found, previous_match)
      if previous_match.nil?
        found * GAP_PENALTY
      else
        (found - previous_match - 1) * GAP_PENALTY
      end
    end

    def self.word_start?(haystack, index)
      index.zero? || WORD_SEPARATORS.include?(haystack[index - 1])
    end
  end

  # The playlist's search filter.
  #
  # Ported from upstream's src/search.rs, a Gtk::Filter subclass with a
  # "search" property that matches a song's search key fuzzily, and reports
  # GTK_FILTER_MATCH_SOME so the list view re-filters on every change.
  #
  # The Ruby bindings cannot subclass Gtk::Filter, and the Gtk::CustomFilter
  # that would stand in for one is only half usable: its match function does
  # receive the item, but the companion Gtk::CustomSorter receives raw
  # pointers rather than objects, so the playlist cannot be filtered by a
  # model and sorted by a model at the same time. The window therefore keeps
  # the visible model itself and asks this object — and FuzzySorter — about
  # each song, which is the same decision upstream's filter makes, taken one
  # level up.
  class FuzzyFilter
    def initialize
      @search = nil
    end

    def search = @search

    def search=(search)
      search.to_s.downcase.then do |needle|
        unless @search == needle
          @search = needle
        end
      end
      search
    end

    # Upstream reports GTK_FILTER_MATCH_SOME, since a song matches or does not
    # depending on the search.
    def strictness = :some

    def match?(song)
      if @search.nil? || @search.empty?
        true
      else
        FuzzyMatcher.match?(song.search_key, @search)
      end
    end
  end
end
