# frozen_string_literal: true

module Amberol
  module Audio
    # Reads the tags and the duration off an audio file.
    #
    # Upstream's src/audio/song.rs gets this from the `lofty` crate; the Ruby
    # bindings have no equivalent gem in the app's closure, so the formats
    # Amberol plays are parsed here: ID3v2 (MP3), Vorbis comments (FLAC, Ogg
    # Vorbis, Opus), MP4/M4A item lists, and RIFF/WAVE headers.
    #
    # Read returns the same shape lofty's Tag presents to song.rs:
    #
    #   {
    #     artist:   String or nil,   # TrackArtist
    #     title:    String or nil,
    #     album:    String or nil,
    #     album_artist: String or nil,
    #     duration: Integer,         # whole seconds
    #     pictures: [{type:, data:}] # :cover_front, :other, :band_logo, …
    #   }
    #
    # Anything it cannot parse comes back as nil rather than raising: a file
    # with no tags is still a playable song.
    module TagReader
      # The ID3v2 picture types, in the order the spec numbers them. Only the
      # three the cover cache looks for are named; the rest keep their index.
      PICTURE_TYPES = {
        0  => :other,
        3  => :cover_front,
        19 => :band_logo,
      }.freeze

      # MPEG audio version 1/2/2.5 bitrate tables for layer III, in kbit/s.
      MPEG_BITRATES = {
        1 => [nil, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, nil],
        2 => [nil, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, nil],
      }.freeze

      MPEG_SAMPLE_RATES = {
        3 => [44_100, 48_000, 32_000, nil],
        2 => [22_050, 24_000, 16_000, nil],
        0 => [11_025, 12_000, 8_000, nil],
      }.freeze

      # Samples per frame for layer III: 1152 for MPEG-1, 576 for MPEG-2/2.5.
      MPEG_SAMPLES_PER_FRAME = {1 => 1152, 2 => 576}.freeze

      # The Vorbis comment field names the app reads, and the MP4 item list
      # atoms that carry the same values.
      VORBIS_FIELDS = {
        "ARTIST"      => :artist,
        "TITLE"       => :title,
        "ALBUM"       => :album,
        "ALBUMARTIST" => :album_artist,
      }.freeze

      MP4_FIELDS = {
        "\xA9ART" => :artist,
        "\xA9nam" => :title,
        "\xA9alb" => :album,
        "aART"    => :album_artist,
      }.freeze

      ID3_TEXT_FRAMES = {
        "TPE1" => :artist,
        "TIT2" => :title,
        "TALB" => :album,
        "TPE2" => :album_artist,
        "TP1"  => :artist,
        "TT2"  => :title,
        "TAL"  => :album,
        "TP2"  => :album_artist,
      }.freeze

      class << self
        def read(path)
          File.open(path, "rb") do |io|
            parse(io, File.size(path))
          end
        rescue SystemCallError, IOError, EOFError, ArgumentError
          nil
        end

        private

          def empty_tag
            {
              artist:       nil,
              title:        nil,
              album:        nil,
              album_artist: nil,
              duration:     0,
              pictures:     [],
            }
          end

          def parse(io, size)
            io.read(12).to_s.then do |head|
              io.rewind
              if head.start_with?("ID3") || mpeg_sync?(head)
                read_mpeg(io, size)
              elsif head.start_with?("fLaC")
                read_flac(io, size)
              elsif head.start_with?("OggS")
                read_ogg(io, size)
              elsif head.start_with?("RIFF") && head[8, 4] == "WAVE"
                read_wave(io, size)
              elsif head[4, 4] == "ftyp"
                read_mp4(io, size)
              end
            end
          end

          def mpeg_sync?(head) = head.bytesize > 1 && head.getbyte(0) == 0xFF && (head.getbyte(1) & 0xE0) == 0xE0

          # --- MP3 / ID3v2 ------------------------------------------------

          def read_mpeg(io, size)
            empty_tag.tap do |tag|
              audio_offset = 0
              if io.read(3) == "ID3"
                audio_offset = read_id3(io, tag)
              end
              io.seek(audio_offset)
              tag[:duration] = mpeg_duration(io, size - audio_offset, tag.delete(:length_ms))
            end
          end

          # Reads the ID3v2 tag the stream is positioned just past the "ID3"
          # magic of, and returns the offset the audio frames start at.
          def read_id3(io, tag)
            io.read(7).then do |header|
              major = header.getbyte(0)
              flags = header.getbyte(2)
              body_size = syncsafe(header[3, 4])
              body = io.read(body_size).to_s
              offset = 0
              if (flags & 0x40) != 0
                offset = extended_header_size(body, major)
              end
              read_id3_frames(
                body,
                offset,
                major,
                tag,
              )
              10 + body_size
            end
          end

          def extended_header_size(body, major)
            if major >= 4
              syncsafe(body[0, 4])
            else
              4 + unpack_be(body[0, 4])
            end
          end

          def read_id3_frames(body, offset, major, tag)
            if major <= 2
              id_size = 3
            else
              id_size = 4
            end
            if major <= 2
              header_size = 6
            else
              header_size = 10
            end

            while offset + header_size <= body.bytesize
              frame_id = body[offset, id_size]
              if frame_id.nil? || frame_id.start_with?("\x00")
                break
              end

              frame_size = id3_frame_size(
                body,
                offset,
                id_size,
                major,
              )
              payload = body[offset + header_size, frame_size].to_s
              store_id3_frame(frame_id, payload, tag)
              offset += header_size + frame_size
            end
          end

          def id3_frame_size(body, offset, id_size, major)
            body[offset + id_size, id_size].then do |raw|
              if major >= 4
                syncsafe(raw)
              else
                unpack_be(raw)
              end
            end
          end

          def store_id3_frame(frame_id, payload, tag)
            field = ID3_TEXT_FRAMES[frame_id]
            if field
              tag[field] ||= decode_id3_text(payload)
            end
            if %w[TLEN TLE].include?(frame_id)
              tag[:length_ms] = decode_id3_text(payload).to_s[/\d+/].to_i
            end
            if frame_id == "APIC"
              tag[:pictures] << decode_apic(payload)
            end
            if frame_id == "PIC"
              tag[:pictures] << decode_pic(payload)
            end
            tag[:pictures].compact!
          end

          # The first byte of a text frame is its encoding; the rest is the
          # string, which may carry a trailing NUL.
          def decode_id3_text(payload)
            payload.getbyte(0).then do |encoding|
              decode_string(payload[1..].to_s, encoding).then do |text|
                # Multi-value frames are NUL-separated in v2.4; the app wants
                # them the way lofty joins them.
                text.split("\x00").reject(&:empty?).join(", ").strip.then do |joined|
                  joined.empty? ? nil : joined
                end
              end
            end
          rescue ArgumentError, TypeError
            nil
          end

          def decode_string(bytes, encoding)
            case encoding
            when 1 then force_utf8(bytes.dup.force_encoding(Encoding::UTF_16).encode(Encoding::UTF_8))
            when 2 then force_utf8(bytes.dup.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8))
            when 3 then force_utf8(bytes.dup.force_encoding(Encoding::UTF_8))
            else force_utf8(bytes.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8))
            end
          rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
            force_utf8(bytes.dup.force_encoding(Encoding::UTF_8))
          end

          def force_utf8(text)
            text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "").delete("\u0000")
          end

          # APIC: encoding, NUL-terminated MIME type, picture type, terminated
          # description, then the image data.
          def decode_apic(payload)
            encoding = payload.getbyte(0)
            mime_end = payload.index("\x00", 1)
            if mime_end.nil?
              nil
            else
              picture_type = payload.getbyte(mime_end + 1)
              data_start = description_end(payload, mime_end + 2, encoding)
              picture(picture_type, payload[data_start..])
            end
          end

          # PIC, the v2.2 shape: encoding, three-character image format,
          # picture type, terminated description, then the image data.
          def decode_pic(payload)
            encoding = payload.getbyte(0)
            picture_type = payload.getbyte(4)
            data_start = description_end(payload, 5, encoding)
            picture(picture_type, payload[data_start..])
          end

          # Skips a description string: one NUL for the single-byte encodings,
          # two aligned NULs for the UTF-16 ones.
          def description_end(payload, offset, encoding)
            if [1, 2].include?(encoding)
              index = offset
              while index + 1 < payload.bytesize && !(payload.getbyte(index).zero? && payload.getbyte(index + 1).zero?)
                index += 2
              end
              index + 2
            else
              (payload.index("\x00", offset) || offset) + 1
            end
          end

          def picture(type, data)
            if data.nil? || data.empty?
              nil
            else
              {type: PICTURE_TYPES.fetch(type.to_i, type.to_i), data: data}
            end
          end

          # Duration from a Xing/Info frame count when the file carries one (so
          # VBR files are right), from TLEN when it does not, and from the
          # first frame's bitrate as a last resort.
          def mpeg_duration(io, audio_size, length_ms)
            frame_header(io).then do |header|
              if header.nil?
                (length_ms.to_i / 1000.0).round
              else
                xing_frames(io, header).then do |frames|
                  if frames.to_i.positive?
                    (frames * header[:samples_per_frame].to_f / header[:sample_rate]).round
                  elsif length_ms.to_i.positive?
                    (length_ms.to_i / 1000.0).round
                  else
                    (audio_size * 8.0 / (header[:bitrate] * 1000)).round
                  end
                end
              end
            end
          end

          # Scans forward for a frame sync and parses the header it starts.
          def frame_header(io)
            start = io.pos
            buffer = io.read(64 * 1024).to_s
            index = 0
            result = nil

            while index + 4 <= buffer.bytesize && result.nil?
              if buffer.getbyte(index) == 0xFF && (buffer.getbyte(index + 1) & 0xE0) == 0xE0
                result = parse_frame_header(buffer[index, 4], start + index)
              end
              index += 1
            end

            result
          end

          def parse_frame_header(bytes, offset)
            version_bits = (bytes.getbyte(1) >> 3) & 0x03
            layer_bits = (bytes.getbyte(1) >> 1) & 0x03
            bitrate_index = (bytes.getbyte(2) >> 4) & 0x0F
            rate_index = (bytes.getbyte(2) >> 2) & 0x03
            padding = (bytes.getbyte(2) >> 1) & 0x01

            sample_rate = MPEG_SAMPLE_RATES.dig(version_bits, rate_index)
            if version_bits == 3
              generation = 1
            else
              generation = 2
            end
            bitrate = MPEG_BITRATES.dig(generation, bitrate_index)

            if sample_rate.nil? || bitrate.nil? || layer_bits != 1
              nil
            else
              {
                offset:            offset,
                bitrate:           bitrate,
                sample_rate:       sample_rate,
                samples_per_frame: MPEG_SAMPLES_PER_FRAME.fetch(generation),
                channel_mode:      (bytes.getbyte(3) >> 6) & 0x03,
                padding:           padding,
                generation:        generation,
              }
            end
          end

          # A Xing or Info header sits in the first frame's side-information
          # area; its second field is the frame count.
          def xing_frames(io, header)
            io.seek(header[:offset])
            frame = io.read(1024).to_s
            index = frame.index("Xing") || frame.index("Info")
            if index.nil?
              nil
            else
              flags = unpack_be(frame[index + 4, 4])
              if (flags & 0x01).zero?
                nil
              else
                unpack_be(frame[index + 8, 4])
              end
            end
          end

          # --- FLAC -------------------------------------------------------

          def read_flac(io, _size)
            empty_tag.tap do |tag|
              io.seek(4)
              last = false
              until last
                header = io.read(4)
                if header.nil? || header.bytesize < 4
                  break
                end

                last = (header.getbyte(0) & 0x80) != 0
                block_type = header.getbyte(0) & 0x7F
                length = unpack_be(header[1, 3])
                body = io.read(length).to_s
                read_flac_block(block_type, body, tag)
              end
            end
          end

          def read_flac_block(block_type, body, tag)
            case block_type
            when 0 then tag[:duration] = flac_duration(body)
            when 4 then read_vorbis_comment(body, tag)
            when 6 then tag[:pictures] << flac_picture(body)
            end
            tag[:pictures].compact!
          end

          # STREAMINFO: the sample rate is 20 bits at bit offset 80, and the
          # total sample count the 36 bits that follow the channel and depth
          # fields.
          def flac_duration(body)
            if body.bytesize < 18
              0
            else
              bits = body[10, 8].unpack1("Q>")
              sample_rate = (bits >> 44) & 0xFFFFF
              total_samples = bits & 0xFFFFFFFFF
              if sample_rate.zero?
                0
              else
                (total_samples.to_f / sample_rate).round
              end
            end
          end

          def flac_picture(body)
            picture_type = unpack_be(body[0, 4])
            mime_length = unpack_be(body[4, 4])
            offset = 8 + mime_length
            description_length = unpack_be(body[offset, 4])
            offset += 4 + description_length + 16
            data_length = unpack_be(body[offset, 4])
            picture(picture_type, body[offset + 4, data_length])
          end

          # --- Ogg (Vorbis and Opus) --------------------------------------

          def read_ogg(io, size)
            empty_tag.tap do |tag|
              packets = ogg_packets(io)
              sample_rate = 48_000
              packets.each do |packet|
                if packet.start_with?("\x01vorbis")
                  sample_rate = packet[12, 4].to_s.unpack1("V").to_i
                end
                if packet.start_with?("\x03vorbis")
                  read_vorbis_comment(packet[7..].to_s, tag)
                end
                if packet.start_with?("OpusTags")
                  read_vorbis_comment(packet[8..].to_s, tag)
                end
              end
              tag[:duration] = ogg_duration(io, size, sample_rate)
            end
          end

          # The first few pages are enough: the identification and comment
          # headers are the first two packets of the stream.
          def ogg_packets(io)
            io.rewind
            [].tap do |packets|
              4.times do
                page = read_ogg_page(io)
                if page.nil?
                  break
                end

                packets.concat(page)
              end
            end
          end

          def read_ogg_page(io)
            header = io.read(27)
            if header.nil? || !header.start_with?("OggS")
              nil
            else
              segments = header.getbyte(26)
              table = io.read(segments).to_s.bytes
              body = io.read(table.sum).to_s
              split_ogg_segments(body, table)
            end
          end

          def split_ogg_segments(body, table)
            [].tap do |packets|
              current = +""
              offset = 0
              table.each do |length|
                current << body[offset, length].to_s
                offset += length
                unless length == 255
                  packets << current
                  current = +""
                end
              end
              unless current.empty?
                packets << current
              end
            end
          end

          # The granule position of the last page is the stream's sample count
          # for Vorbis, and its 48kHz sample count for Opus.
          def ogg_duration(io, size, sample_rate)
            last_granule(io, size).then do |granule|
              if granule.to_i.positive? && sample_rate.positive?
                (granule.to_f / sample_rate).round
              else
                0
              end
            end
          end

          def last_granule(io, size)
            window = [size, 65_536].min
            io.seek(size - window)
            buffer = io.read(window).to_s
            index = buffer.rindex("OggS")
            if index.nil?
              nil
            else
              buffer[index + 6, 8].to_s.unpack1("Q<")
            end
          end

          # A Vorbis comment block: vendor string, then count, then
          # "FIELD=value" entries. METADATA_BLOCK_PICTURE carries a base64
          # FLAC picture block.
          def read_vorbis_comment(body, tag)
            vendor_length = body[0, 4].to_s.unpack1("V").to_i
            offset = 4 + vendor_length
            count = body[offset, 4].to_s.unpack1("V").to_i
            offset += 4

            count.times do
              length = body[offset, 4].to_s.unpack1("V").to_i
              entry = body[offset + 4, length].to_s
              offset += 4 + length
              store_vorbis_field(entry, tag)
            end
          end

          def store_vorbis_field(entry, tag)
            entry.split("=", 2).then do |(name, value)|
              field = VORBIS_FIELDS[name.to_s.upcase]
              if field
                tag[field] ||= force_utf8(value.to_s.dup.force_encoding(Encoding::UTF_8))
              end
              if name.to_s.upcase == "METADATA_BLOCK_PICTURE"
                tag[:pictures] << decode_block_picture(value)
              end
              tag[:pictures].compact!
            end
          end

          def decode_block_picture(value)
            require "base64"
            flac_picture(Base64.decode64(value.to_s))
          rescue ArgumentError
            nil
          end

          # --- MP4 / M4A --------------------------------------------------

          def read_mp4(io, size)
            empty_tag.tap do |tag|
              walk_mp4(
                io,
                0,
                size,
                tag,
              )
            end
          end

          # The container is a tree of length-prefixed atoms; only the two
          # branches carrying the metadata and the timing are walked into.
          def walk_mp4(io, offset, limit, tag)
            while offset + 8 <= limit
              io.seek(offset)
              header = io.read(8)
              if header.nil? || header.bytesize < 8
                break
              end

              length = unpack_be(header[0, 4])
              name = header[4, 4]
              if length < 8
                break
              end

              read_mp4_atom(
                io,
                name,
                offset,
                length,
                tag,
              )
              offset += length
            end
          end

          def read_mp4_atom(io, name, offset, length, tag)
            case name
            when "moov", "udta", "trak", "mdia" then walk_mp4(
              io,
              offset + 8,
              offset + length,
              tag,
            )
            when "meta" then walk_mp4(
              io,
              offset + 12,
              offset + length,
              tag,
            )
            when "ilst" then read_mp4_ilst(
              io,
              offset + 8,
              offset + length,
              tag,
            )
            when "mvhd" then tag[:duration] = mp4_duration(io, offset)
            end
          end

          def mp4_duration(io, offset)
            io.seek(offset + 8)
            io.read(20).to_s.then do |body|
              version = body.getbyte(0)
              if version == 1
                io.seek(offset + 8)
                io.read(32).to_s.then do |long|
                  timescale = unpack_be(long[20, 4])
                  duration = long[24, 8].to_s.unpack1("Q>").to_i
                  scaled_duration(duration, timescale)
                end
              else
                scaled_duration(unpack_be(body[16, 4]), unpack_be(body[12, 4]))
              end
            end
          end

          def scaled_duration(duration, timescale)
            if timescale.to_i.positive?
              (duration.to_f / timescale).round
            else
              0
            end
          end

          def read_mp4_ilst(io, offset, limit, tag)
            while offset + 8 <= limit
              io.seek(offset)
              header = io.read(8)
              if header.nil? || header.bytesize < 8
                break
              end

              length = unpack_be(header[0, 4])
              name = header[4, 4].to_s.dup.force_encoding(Encoding::BINARY)
              if length < 8
                break
              end

              store_mp4_item(name, io.read(length - 8).to_s, tag)
              offset += length
            end
          end

          # Each item holds a "data" atom: four bytes of type, four reserved,
          # then the value.
          def store_mp4_item(name, body, tag)
            index = body.index("data")
            if index
              payload = body[(index + 12)..].to_s
              field = MP4_FIELDS[name]
              if field
                tag[field] ||= force_utf8(payload.dup.force_encoding(Encoding::UTF_8))
              end
              if name == "covr"
                tag[:pictures] << picture(3, payload)
              end
              tag[:pictures].compact!
            end
          end

          # --- RIFF / WAVE ------------------------------------------------

          def read_wave(io, size)
            empty_tag.tap do |tag|
              io.seek(12)
              byte_rate = 0
              data_size = 0

              while io.pos + 8 <= size
                header = io.read(8)
                if header.nil? || header.bytesize < 8
                  break
                end

                name = header[0, 4]
                length = header[4, 4].to_s.unpack1("V").to_i
                body = io.read(length).to_s
                if name == "fmt "
                  byte_rate = body[8, 4].to_s.unpack1("V").to_i
                end
                if name == "data"
                  data_size = length
                end
                if name == "LIST"
                  read_wave_info(body, tag)
                end
                io.seek(io.pos + (length % 2))
              end

              if byte_rate.positive?
                tag[:duration] = (data_size.to_f / byte_rate).round
              end
            end
          end

          # A LIST/INFO chunk: INAM, IART and IPRD are the title, artist and
          # album a WAVE file can carry.
          def read_wave_info(body, tag)
            if body.start_with?("INFO")
              offset = 4
              while offset + 8 <= body.bytesize
                name = body[offset, 4]
                length = body[offset + 4, 4].to_s.unpack1("V").to_i
                value = body[offset + 8, length].to_s
                case name
                when "INAM" then tag[:title] ||= force_utf8(value.dup.force_encoding(Encoding::UTF_8))
                when "IART" then tag[:artist] ||= force_utf8(value.dup.force_encoding(Encoding::UTF_8))
                when "IPRD" then tag[:album] ||= force_utf8(value.dup.force_encoding(Encoding::UTF_8))
                end
                offset += 8 + length + (length % 2)
              end
            end
          end

          # --- Shared -----------------------------------------------------

          def unpack_be(bytes)
            bytes.to_s.bytes.inject(0) { |value, byte| (value << 8) | byte }
          end

          # A syncsafe integer keeps the high bit of every byte clear, so a
          # tag's size can never look like a frame sync.
          def syncsafe(bytes)
            bytes.to_s.bytes.inject(0) { |value, byte| (value << 7) | (byte & 0x7F) }
          end
      end
    end
  end
end
