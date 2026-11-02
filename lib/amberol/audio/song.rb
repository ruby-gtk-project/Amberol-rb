# frozen_string_literal: true

require "digest"
require "gtk4"
require_relative "../i18n"
require_relative "cover_cache"
require_relative "tag_reader"

module Amberol
  module Audio
    # The metadata read off one file.
    #
    # Ported from the SongData struct in upstream's src/audio/song.rs: the
    # tags, the cover art the cache resolved for them, the uuid hashed from
    # the display name and the tags, and the duration.
    class SongData
      attr_reader :artist, :title, :album, :cover_art, :cover_uuid, :uuid, :duration, :file

      # Upstream's SongData::default: the placeholder an unreadable or
      # non-audio file gets, which Song::from_uri recognises and rejects.
      def self.invalid
        new(
          artist:   "Invalid Artist",
          title:    "Invalid Title",
          album:    "Invalid Album",
          duration: 0,
          file:     Gio::File.new_for_path("/does-not-exist"),
          valid:    false,
        )
      end

      # Reads a file's tags, cover art and duration. Anything that is not
      # audio — a playlist, an image, a file with no readable header — comes
      # back as the invalid placeholder.
      def self.from_uri(uri)
        Gio::File.new_for_uri(uri).then do |file|
          path = file.path
          if path.nil? || !audio?(path)
            invalid
          else
            from_path(file, path)
          end
        end
      end

      def self.from_path(file, path)
        TagReader.read(path).then do |tag|
          if tag.nil?
            invalid
          else
            build(file, path, tag)
          end
        end
      end

      def self.build(file, path, tag)
        CoverCache.global.cover_art(path, tag).then do |cover|
          new(
            artist:     presence(tag[:artist]),
            title:      presence(tag[:title]),
            album:      presence(tag[:album]),
            duration:   tag[:duration].to_i,
            file:       file,
            cover_art:  cover&.first,
            cover_uuid: cover&.last,
            uuid:       uuid_for(file, tag),
          )
        end
      end

      # Upstream guesses the content type from the path and rejects anything
      # that is not audio, plus the playlist type that claims to be.
      def self.audio?(path)
        Gio::ContentType.guess(path, nil).then do |(mime_type, _uncertain)|
          mime_type.to_s.start_with?("audio") && !mime_type.to_s.end_with?("x-mpegurl")
        end
      end

      # The uuid identifies a song across runs: the display name plus whatever
      # tags it carries, hashed.
      def self.uuid_for(file, tag)
        Digest::SHA256.new.then do |hasher|
          hasher.update(display_name(file))
          hasher.update(tag[:artist].to_s)
          hasher.update(tag[:title].to_s)
          hasher.update(tag[:album].to_s)
          hasher.hexdigest
        end
      end

      def self.display_name(file)
        file.query_info("standard::display-name", :none).display_name.to_s
      rescue GLib::Error
        file.basename.to_s
      end

      def self.presence(value)
        value.to_s.strip.then { |text| text.empty? ? nil : text }
      end

      def initialize(file:, duration: 0, artist: nil, title: nil, album: nil,
                     cover_art: nil, cover_uuid: nil, uuid: nil, valid: true)
        @file = file
        @duration = duration
        @artist = artist
        @title = title
        @album = album
        @cover_art = cover_art
        @cover_uuid = cover_uuid
        @uuid = uuid
        @valid = valid
      end

      def valid? = @valid

      def uri = @file.uri.to_s

      def cover_texture = @cover_art&.texture
      def cover_palette = @cover_art&.palette
      def cover_cache = @cover_art&.cache
    end

    # One song in the queue.
    #
    # Ported from upstream's src/audio/song.rs. It is a GObject so a
    # Gio::ListStore can hold it and the playlist's ListView can bind to it;
    # upstream's "playing" and "selected" properties are plain attributes here,
    # with the notifications they carried delivered to the listeners the
    # playlist registers — the Ruby bindings cannot install a property on a
    # subclass, and the rows need nothing else from the property system.
    class Song < GLib::Object
      type_register

      def self.from_uri(uri)
        new(uri).then { |song| song.valid? ? song : nil }
      end

      def self.empty = new(nil)

      def initialize(uri)
        super()
        @playing = false
        @selected = false
        @listeners = []
        if uri.nil?
          @data = SongData.invalid
        else
          @data = SongData.from_uri(uri)
        end
      end

      def valid? = @data.valid?

      # Upstream's Song::equals: the uuid when both songs have one, the uri
      # otherwise.
      def equals?(other)
        if uuid && other.uuid
          uuid == other.uuid
        else
          uri == other.uri
        end
      end

      def uri = @data.uri
      def file = @data.file
      def uuid = @data.uuid
      def duration = @data.duration

      def artist = @data.artist || I18n.i18n("Unknown artist")
      def title = @data.title || I18n.i18n("Unknown title")
      def album = @data.album || I18n.i18n("Unknown album")

      def cover_texture = @data.cover_texture
      def cover_palette = @data.cover_palette
      def cover_color = @data.cover_palette&.first
      def cover_uuid = @data.cover_uuid
      def cover_cache = @data.cover_cache

      def search_key = "#{artist} #{album} #{title}"

      def playing? = @playing

      def set_playing(playing)
        playing.then do |value|
          unless @playing == value
            @playing = value
            notify(:playing)
          end
        end
      end

      def selected? = @selected

      def set_selected(selected)
        selected.then do |value|
          unless @selected == value
            @selected = value
            notify(:selected)
          end
        end
      end

      # Registers a listener for the two notifications upstream emits on a
      # song: :playing and :selected. The block is handed the song and the
      # property name.
      def on_change(&block)
        @listeners << block
        block
      end

      def remove_listener(block) = @listeners.delete(block)

      def to_s
        "Song { uuid: #{uuid}, uri: #{uri}, artist: '#{artist}', title: '#{title}' }"
      end

      private

        def notify(property)
          @listeners.each { |listener| listener.call(self, property) }
        end
    end
  end
end
