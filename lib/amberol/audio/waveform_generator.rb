# frozen_string_literal: true

require "gstreamer"
require "json"
require_relative "../utils"
require_relative "controller"

module Amberol
  module Audio
    # Generates and caches a song's waveform.
    #
    # Ported from upstream's src/audio/waveform_generator.rs: for every song
    # the player switches to, it either loads cached peaks off disk or builds
    # a throwaway analysis pipeline — `uridecodebin ! audioconvert !
    # audio/x-raw,channels=2 ! level ! fakesink` — and collects the `level`
    # element's peak-dB pairs off the bus, one every 250ms, until end of
    # stream. {WaveformView} is the only thing reading #peaks: it has no idea
    # whether they came from the cache or were just generated.
    #
    # Upstream drives the pipeline through `gst::parse::launch` and GstPlay
    # has no equivalent to build an arbitrary analysis graph, so this is where
    # the port reaches past GstPlay for the `gstreamer` gem's `Gst` namespace
    # — the same one upstream's gstreamer-rs crate wraps.
    class WaveformGenerator
      include Controller

      # Upstream's level element: a report every 250ms.
      LEVEL_INTERVAL_NS = 250_000_000

      PIPELINE_DESCRIPTION =
        "uridecodebin name=uridecodebin ! audioconvert ! " \
        "audio/x-raw,channels=2 ! level name=level interval=#{LEVEL_INTERVAL_NS} ! " \
        "fakesink name=faked"

      def initialize
        @song = nil
        @peaks = nil
        @pipeline = nil
        @bus_watch_id = nil
        @listeners = []
      end

      def peaks = @peaks

      def has_peaks? = !@peaks.nil?

      # Registers a listener for upstream's "has-peaks" notification. The
      # block is called with no arguments whenever #peaks changes.
      def on_peaks_changed(&block)
        @listeners << block
        block
      end

      def set_song(song)
        @song = song
        load_peaks
      end

      def dispose
        stop_pipeline
      end

      private

        def load_peaks
          @song.then do |song|
            unless song.nil? || song.uuid.nil?
              cache_path(song.uuid).then do |path|
                if File.exist?(path)
                  load_peaks_cache(path)
                else
                  generate_peaks
                end
              end
            end
          end
        end

        def load_peaks_cache(path)
          JSON.parse(File.read(path)).then do |decoded|
            @peaks = decoded.map { |pair| Array(pair).first(2).map(&:to_f) }
            notify_peaks_changed
          end
        rescue JSON::ParserError, SystemCallError
          generate_peaks
        end

        def save_peaks
          @peaks.then do |peaks|
            unless peaks.nil? || @song.nil? || @song.uuid.nil?
              File.write(cache_path(@song.uuid), JSON.generate(peaks))
            end
          end
          notify_peaks_changed
        end

        def cache_path(uuid) = File.join(Utils.cache_subdir("waveforms"), "#{uuid}.json")

        def generate_peaks
          stop_pipeline
          @peaks = []

          song = @song
          if song.nil?
            @peaks = nil
            notify_peaks_changed
          else
            build_pipeline(song)
          end
        end

        def build_pipeline(song)
          pipeline, error = Gst.parse_launch(PIPELINE_DESCRIPTION)
          if pipeline.nil?
            warn("Unable to generate the waveform: #{error.message}")
            @peaks = nil
            notify_peaks_changed
          else
            start_pipeline(pipeline, song)
          end
        end

        def start_pipeline(pipeline, song)
          pipeline.get_by_name("uridecodebin").uri = song.uri
          configure_sink(pipeline)
          watch_bus(pipeline)

          if pipeline.play == Gst::StateChangeReturn::FAILURE
            warn("Unable to generate the waveform: pipeline failed to start playing")
            pipeline.stop
            @peaks = nil
            notify_peaks_changed
          else
            @pipeline = pipeline
          end
        end

        def configure_sink(pipeline)
          pipeline.get_by_name("faked").then do |sink|
            sink.set_property("qos", false)
            sink.set_property("sync", false)
          end
        end

        def watch_bus(pipeline)
          @bus_watch_id = pipeline.bus.add_watch do |_bus, message|
            handle_message(pipeline, message)
          end
        end

        def handle_message(pipeline, message)
          case message.type
          when Gst::MessageType::EOS then finish_pipeline(pipeline)
          when Gst::MessageType::ERROR then abort_pipeline(pipeline, message)
          when Gst::MessageType::ELEMENT then collect_peak(message)
          end
          @pipeline.nil? ? false : true
        end

        def collect_peak(message)
          structure = message.structure
          if structure && structure.name == "level"
            peak_db = structure["peak"].value
            @peaks << peak_db.first(2).map { |db| 10.0**(db / 20.0) }
          end
        end

        def finish_pipeline(pipeline)
          pipeline.stop
          @pipeline = nil
          @bus_watch_id = nil
          save_peaks
        end

        def abort_pipeline(pipeline, message)
          error, debug = message.parse_error
          warn("Pipeline error: #{error.message} (#{debug})")
          pipeline.stop
          @pipeline = nil
          @bus_watch_id = nil
          @peaks = nil
          save_peaks
        end

        def stop_pipeline
          unless @pipeline.nil?
            unless @bus_watch_id.nil?
              @pipeline.bus.remove_watch
            end
            @pipeline.stop
          end
          @pipeline = nil
          @bus_watch_id = nil
        end

        def notify_peaks_changed
          @listeners.each(&:call)
        end
    end
  end
end
