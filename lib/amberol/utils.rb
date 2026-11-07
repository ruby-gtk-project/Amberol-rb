# frozen_string_literal: true

require "fileutils"
require "gtk4"
require_relative "config"
require_relative "settings"

module Amberol
  # Free functions shared across the app.
  #
  # Ported from upstream's src/utils.rs: the settings accessor, the time
  # formatters, the cover-art loading/caching/palette extraction, the
  # Nautilus-like file ordering, the recursive folder enumeration and the
  # ".pls" playlist cache.
  module Utils
    # The base cover size is 192px, doubled to account for HiDPI: better to
    # scale down on a display with a scaling factor of 1 than to scale up on
    # one with a factor of 2.
    COVER_SIZE = 192 * 2

    # How many colours the recolouring palette carries, and how coarsely the
    # cover's pixels are bucketed while looking for them.
    PALETTE_SIZE = 5
    PALETTE_BUCKET_BITS = 4

    # A sample every few pixels is enough to find the dominant colours, and it
    # keeps a 384x384 cover's palette extraction off the frame budget.
    PALETTE_SAMPLE_STEP = 4

    class << self
      def settings_manager = Settings.default

      # An explicit LEFT-TO-RIGHT MARK keeps the MINUS SIGN in front of the
      # remaining time in RTL locales, instead of being flipped to the end.
      def format_remaining_time(time) = "‎−#{format_time(time)}"

      def format_time(time)
        time.to_i.then do |seconds|
          format("%d:%02d", (seconds - (seconds % 60)) / 60, seconds % 60)
        end
      end

      # Decodes cover art held in memory and scales it to COVER_SIZE along its
      # longer edge. Returns nil when the bytes are not an image.
      def load_cover_pixbuf(data)
        GdkPixbuf::PixbufLoader.new.then do |loader|
          loader.write(data)
          loader.close
          loader.pixbuf.then { |pixbuf| scale_cover(pixbuf) }
        end
      rescue GLib::Error, ArgumentError
        nil
      end

      # Writes the cover to the cover cache as a PNG and returns its path, so
      # the controllers can hand a file to anything that cannot take a texture.
      # An existing file is left alone: the uuid already identifies the cover.
      def cache_cover_art(uuid, pixbuf)
        File.join(cache_subdir("covers"), "#{uuid}.png").tap do |path|
          unless File.exist?(path)
            pixbuf.save(path, "png")
          end
        end
      rescue GLib::Error, SystemCallError
        nil
      end

      # The dominant colours of a cover, as Gdk::RGBA, most common first.
      #
      # Upstream runs color_thief's median cut over the pixel buffer; this
      # buckets the sampled pixels into a coarse colour cube and averages each
      # of the most populated buckets, which picks out the same broad areas of
      # colour a cover is made of.
      def load_palette(pixbuf)
        colour_buckets(pixbuf).then do |buckets|
          buckets.sort_by { |_key, bucket| -bucket[:count] }
                 .first(PALETTE_SIZE)
                 .map { |_key, bucket| bucket_to_rgba(bucket) }
                 .then { |colours| colours.empty? ? nil : colours }
        end
      end

      # Orders two files the way Nautilus orders a directory listing: by the
      # parent's name first (relative to `base` when one is given), then by the
      # file's own name, with dot- and hash-prefixed names sorted last.
      def cmp_two_files(base, file_a, file_b)
        parent_key(base, file_a).then do |parent_a|
          parent_key(base, file_b).then do |parent_b|
            cmp_like_nautilus(parent_a, parent_b).then do |order|
              if order.zero?
                cmp_like_nautilus(file_a.basename.to_s, file_b.basename.to_s)
              else
                order
              end
            end
          end
        end
      end

      # Every regular file under `folder`, in the order the names imply.
      # gio::FileEnumerator has no guaranteed order, so the names are what the
      # queue ends up ordered by.
      def load_files_from_folder(folder, recursive)
        load_files_from_folder_internal(folder, folder, recursive)
      end

      # Records the queue as a ".pls" playlist in the cache directory, which is
      # what the "Restore Playlist" button reads back.
      def store_playlist(queue)
        GLib::KeyFile.new.then do |pls|
          pls.set_string("playlist", "X-GNOME-Title", "Amberol's current playlist")
          pls.set_integer("playlist", "NumberOfEntries", queue.n_songs)
          queue.visible_songs.each_with_index do |song, index|
            pls.set_value("playlist", "File#{index}", song.file.path.to_s)
          end
          File.write(playlist_cache_path, pls.to_data)
        end
      rescue GLib::Error, SystemCallError
        nil
      end

      # The files the previous run left in the playlist cache, or nil when
      # there is no cache to read.
      def load_cached_songs
        GLib::KeyFile.new.then do |pls|
          begin
            pls.load_from_file(playlist_cache_path)
          rescue GLib::Error
            break nil
          end

          begin
            n_entries = pls.get_integer("playlist", "NumberOfEntries")
          rescue GLib::Error
            n_entries = 0
          end

          (0...n_entries).filter_map do |index|
            begin
              Gio::File.new_for_path(pls.get_value("playlist", "File#{index}"))
            rescue GLib::Error
              nil
            end
          end
        end
      end

      def has_cached_playlist? = File.exist?(playlist_cache_path)

      def playlist_cache_path = File.join(cache_subdir("playlists"), "current.pls")

      # Removes every cover PNG this run wrote, which is what clearing the
      # queue means for the on-disk half of the cover cache.
      def clear_cover_cache
        Dir.glob(File.join(cache_subdir("covers"), "*.png")).each do |path|
          FileUtils.rm_f(path)
        end
      end

      # `GLib.user_cache_dir` resolves `$XDG_CACHE_HOME` (falling back to
      # `$HOME/.cache`) once per process the first time GLib itself needs it,
      # which can be before this app ever runs -- a test that overrides
      # `ENV["XDG_CACHE_HOME"]` to sandbox itself would otherwise still land
      # on the real cache dir. Reading the env var directly here keeps this
      # call live to whatever the current process has it set to.
      def cache_subdir(name)
        File.join(
          ENV["XDG_CACHE_HOME"].then { |value| value.nil? || value.empty? ? File.join(Dir.home, ".cache") : value },
          "amberol",
          name,
        ).tap do |path|
          FileUtils.mkdir_p(path, mode: 0o755)
        end
      end

      private

        def scale_cover(pixbuf)
          pixbuf.then do |source|
            (source.width.to_f / source.height).then do |ratio|
              width = COVER_SIZE
              height = (COVER_SIZE / ratio).to_i
              if ratio <= 1.0
                width = (COVER_SIZE * ratio).to_i
                height = COVER_SIZE
              end
              source.scale_simple([width, 1].max, [height, 1].max, :bilinear)
            end
          end
        end

        def colour_buckets(pixbuf)
          shift = 8 - PALETTE_BUCKET_BITS
          channels = pixbuf.n_channels
          rowstride = pixbuf.rowstride
          pixels = pixbuf.pixels
          buckets = {}

          (0...pixbuf.height).step(PALETTE_SAMPLE_STEP) do |y|
            (0...pixbuf.width).step(PALETTE_SAMPLE_STEP) do |x|
              offset = (y * rowstride) + (x * channels)
              alpha = 255
              if channels > 3
                alpha = pixels[offset + 3].to_i
              end
              if alpha > 127
                red = pixels[offset].to_i
                green = pixels[offset + 1].to_i
                blue = pixels[offset + 2].to_i
                key = [red >> shift, green >> shift, blue >> shift]
                bucket = buckets[key] ||= {count: 0, red: 0, green: 0, blue: 0}
                bucket[:count] += 1
                bucket[:red] += red
                bucket[:green] += green
                bucket[:blue] += blue
              end
            end
          end

          buckets
        end

        def bucket_to_rgba(bucket)
          bucket[:count].then do |count|
            Gdk::RGBA.new(
              bucket[:red].to_f / count / 255.0,
              bucket[:green].to_f / count / 255.0,
              bucket[:blue].to_f / count / 255.0,
              1.0,
            )
          end
        end

        def parent_key(base, file)
          file.parent.then do |parent|
            if parent.nil?
              file.basename.to_s
            else
              relative_parent_key(base, parent)
            end
          end
        end

        def relative_parent_key(base, parent)
          if base.nil?
            parent.basename.to_s
          else
            (base.get_relative_path(parent) || parent.basename).to_s
          end
        end

        # Dot- and hash-prefixed names sort last; everything else sorts by a
        # natural key, so "track2" comes before "track10".
        def cmp_like_nautilus(name_a, name_b)
          sort_last?(name_a).then do |last_a|
            sort_last?(name_b).then do |last_b|
              if last_a == last_b
                natural_key(name_a) <=> natural_key(name_b)
              else
                last_a ? 1 : -1
              end
            end
          end
        end

        def sort_last?(name) = name.start_with?(".", "#")

        # Splits a name into alternating text and number runs, so numbers
        # compare as numbers. The leading 0 and the trailing name keep the
        # comparison total: every key is an array of [kind, value] pairs.
        def natural_key(name)
          name.downcase.scan(/\d+|\D+/).map do |chunk|
            if chunk.match?(/\A\d+\z/)
              [0, chunk.to_i, ""]
            else
              [1, 0, chunk]
            end
          end
        end

        def load_files_from_folder_internal(base, folder, recursive)
          enumerate(folder).then do |children|
            children.flat_map do |child, file_type|
              if recursive && file_type == Gio::FileType::DIRECTORY
                load_files_from_folder_internal(base, child, recursive)
              elsif file_type == Gio::FileType::REGULAR
                [child]
              else
                []
              end
            end.sort { |a, b| cmp_two_files(base, a, b) }
          end
        end

        def enumerate(folder)
          folder.enumerate_children(
            "standard::name,standard::type",
            :nofollow_symlinks,
          ).then do |enumerator|
            [].tap do |children|
              while (info = enumerator.next_file)
                children << [folder.get_child(info.name), info.file_type]
              end
              enumerator.close
            end
          end
        rescue GLib::Error
          []
        end
    end
  end
end
