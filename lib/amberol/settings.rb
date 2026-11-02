# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "config"

module Amberol
  # The application's stored preferences.
  #
  # Ported from upstream's data/io.bassi.Amberol.gschema.xml: the same five
  # keys, the same defaults, and the same ReplayGainMode enum nicks.
  #
  # Upstream reads them through GSettings, which needs a schema compiled into
  # a directory GLib searches; requiring an install step before the app can be
  # run from a checkout is worse than the alternative, so the keys are backed
  # by a small JSON file under XDG_CONFIG_HOME instead. Everything else — the
  # defaults, the change notifications the window and the application listen
  # for — behaves as the schema says.
  class Settings
    DEFAULTS = {
      "window-width"      => 600,
      "window-height"     => 300,
      "enable-recoloring" => true,
      "replay-gain"       => "off",
      "background-play"   => true,
    }.freeze

    # The <enum> the "replay-gain" key is typed with, nick to value.
    REPLAY_GAIN_VALUES = {
      "album" => 0,
      "track" => 1,
      "off"   => 2,
    }.freeze

    def self.default = @default ||= new

    def initialize(path: nil)
      @path = path || default_path
      @values = DEFAULTS.merge(read)
      @listeners = {}
    end

    def location = @path

    def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

    def []=(key, value)
      key.to_s.then do |name|
        @values[name] = value
        write
        notify(name)
      end
      value
    end

    # GSettings' typed getters, so callers read a key the way upstream does.
    def int(key) = self[key].to_i
    def boolean(key) = self[key] == true
    def string(key) = self[key].to_s

    # The enum key's integer value, as gio::Settings::enum_ returns it.
    def enum(key) = REPLAY_GAIN_VALUES.fetch(string(key), REPLAY_GAIN_VALUES["off"])

    def set_int(key, value) = self[key] = value.to_i
    def set_boolean(key, value) = self[key] = (value == true)
    def set_string(key, value) = self[key] = value.to_s

    def set_enum(key, value)
      self[key] = REPLAY_GAIN_VALUES.key(value) || "off"
    end

    # Runs the block whenever `key` changes, the way gio::Settings'
    # "changed::<key>" signal does. The block is handed this settings object
    # and the key, matching upstream's connect_changed closures.
    def connect_changed(key, &block)
      (@listeners[key.to_s] ||= []) << block
      block
    end

    DEFAULTS.each_key do |key|
      method_name = key.tr("-", "_")
      define_method(method_name) { self[key] }
      define_method(:"#{method_name}=") { |value| self[key] = value }
    end

    private

      def notify(key)
        @listeners.fetch(key, []).each { |listener| listener.call(self, key) }
      end

      def default_path
        File.join(
          ENV.fetch("XDG_CONFIG_HOME", File.expand_path("~/.config")),
          "amberol",
          "#{Config.settings_id}.json",
        )
      end

      def read
        JSON.parse(File.read(@path)).then do |parsed|
          parsed.is_a?(Hash) ? parsed.slice(*DEFAULTS.keys) : {}
        end
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def write
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, "#{JSON.pretty_generate(@values)}\n")
      rescue SystemCallError
        nil
      end
  end
end
