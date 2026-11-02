# frozen_string_literal: true

require "digest"
require "gtk4"
require_relative "../utils"

module Amberol
  module Audio
    # One album's cover art: the texture the UI draws, the palette the window
    # recolours itself from, and the PNG the cache wrote for the controllers.
    #
    # Ported from the CoverArt struct in upstream's src/audio/cover_cache.rs.
    class CoverArt
      attr_reader :texture, :palette, :cache

      def initialize(texture:, palette:, cache: nil)
        @texture = texture
        @palette = palette
        @cache = cache
      end
    end

    # The process-wide cover art cache.
    #
    # Ported from upstream's src/audio/cover_cache.rs. Covers are keyed on the
    # album, its artist and the containing directory — so every track of an
    # album shares one texture and one palette — and on the file's path when
    # there is no album tag to key on.
    #
    # Upstream's cache is a Mutex<HashMap> behind a OnceCell because songs are
    # loaded off the main thread; the port loads them from a main-context idle
    # callback, so a plain hash behind the same `global` accessor is enough.
    class CoverCache
      # The cover files Amberol looks for next to a song when its tags carry
      # no embedded picture, in the order upstream tries them.
      EXTERNAL_BASENAMES = %w[Cover cover Folder folder].freeze
      EXTERNAL_EXTENSIONS = %w[jpg png].freeze

      # The embedded picture types upstream accepts, best first.
      PICTURE_PREFERENCE = %i[cover_front other band_logo].freeze

      def self.global = @global ||= new

      def initialize
        @entries = {}
      end

      # Returns [CoverArt, uuid] for a song's tag, or nil when the song has no
      # cover art at all.
      def cover_art(path, tag)
        cover_uuid(path, tag).then do |uuid|
          @entries.fetch(uuid, nil).then do |cached|
            if cached
              [cached, uuid]
            else
              load_entry(path, tag, uuid)
            end
          end
        end
      end

      def lookup(uuid) = @entries[uuid]

      def clear
        @entries.clear
        Utils.clear_cover_cache
      end

      private

        def load_entry(path, tag, uuid)
          load_cover_data(path, tag).then do |data|
            if data.nil?
              nil
            else
              build_entry(data, uuid)
            end
          end
        end

        def build_entry(data, uuid)
          Utils.load_cover_pixbuf(data).then do |pixbuf|
            if pixbuf.nil?
              nil
            else
              Utils.load_palette(pixbuf).then do |palette|
                if palette.nil?
                  nil
                else
                  entry = CoverArt.new(
                    texture: Gdk::Texture.new(pixbuf),
                    palette: palette,
                    cache:   Utils.cache_cover_art(uuid, pixbuf),
                  )
                  @entries[uuid] = entry
                  [entry, uuid]
                end
              end
            end
          end
        end

        # The embedded picture wins: it is already in a hot cache, where
        # looking for a separate file would cost a directory read per song.
        def load_cover_data(path, tag)
          embedded_picture(tag).then do |picture|
            if picture
              picture[:data]
            else
              external_cover(path)
            end
          end
        end

        def embedded_picture(tag)
          Array(tag[:pictures]).then do |pictures|
            PICTURE_PREFERENCE.filter_map do |type|
              pictures.find { |picture| picture[:type] == type }
            end.first
          end
        end

        def external_cover(path)
          File.dirname(path).then do |directory|
            external_names.filter_map do |name|
              candidate = File.join(directory, name)
              File.file?(candidate) ? File.binread(candidate) : nil
            end.first
          end
        rescue SystemCallError
          nil
        end

        def external_names
          EXTERNAL_BASENAMES.flat_map do |basename|
            EXTERNAL_EXTENSIONS.map { |extension| "#{basename}.#{extension}" }
          end
        end

        # The album, its artist and the parent directory identify a cover, so
        # every track of an album shares one entry; a song with no album tag
        # falls back to its own path.
        def cover_uuid(path, tag)
          Digest::SHA256.new.then do |hasher|
            if tag[:album].to_s.empty?
              hasher.update(path.to_s)
            else
              hasher.update(tag[:album].to_s)
              hasher.update((tag[:album_artist] || tag[:artist]).to_s)
              hasher.update(File.dirname(path.to_s))
            end
            hasher.hexdigest
          end
        end
    end
  end
end
