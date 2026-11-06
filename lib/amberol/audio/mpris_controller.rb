# frozen_string_literal: true

require "gtk4"
require_relative "../config"
require_relative "controller"

module Amberol
  module Audio
    # Exposes playback over D-Bus under org.mpris.MediaPlayer2, so GNOME
    # Shell's media controls, keyboard media keys and other MPRIS clients can
    # drive Amberol.
    #
    # Ported from upstream's src/audio/mpris_controller.rs, which builds this
    # on the `mpris_server` crate. There is no Ruby binding for that, or for
    # any other MPRIS server library — this is GDBus itself, through the
    # `Gio::DBus*` classes the gtk4 gem's glib2/gio2 already carry: a
    # DBusNodeInfo parsed from each interface's introspection XML,
    # Gio::DBusConnection#register_object to answer method calls and property
    # reads, and Properties.PropertiesChanged / Player.Seeked signals emitted
    # by hand for the notifications upstream's Player::set_metadata and
    # friends send.
    #
    # `sender` is the player's process_action proc, exactly as GstBackend and
    # the other controllers take it: MPRIS method calls become
    # PlaybackActions posted back to the player, and the four Controller
    # notifications update what this controller answers queries with.
    class MprisController
      include Controller

      OBJECT_PATH = "/org/mpris/MediaPlayer2"
      ROOT_INTERFACE = "org.mpris.MediaPlayer2"
      PLAYER_INTERFACE = "org.mpris.MediaPlayer2.Player"
      PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"

      # org.freedesktop.DBus.RequestName flags: DO_NOT_QUEUE. Amberol does
      # not want to wait in line behind another instance for this name.
      REQUEST_NAME_DO_NOT_QUEUE = 4

      ROOT_XML = <<~XML
        <node>
          <interface name="org.mpris.MediaPlayer2">
            <method name="Raise"/>
            <method name="Quit"/>
            <property name="CanQuit" type="b" access="read"/>
            <property name="CanRaise" type="b" access="read"/>
            <property name="HasTrackList" type="b" access="read"/>
            <property name="Identity" type="s" access="read"/>
            <property name="DesktopEntry" type="s" access="read"/>
            <property name="SupportedUriSchemes" type="as" access="read"/>
            <property name="SupportedMimeTypes" type="as" access="read"/>
          </interface>
        </node>
      XML

      PLAYER_XML = <<~XML
        <node>
          <interface name="org.mpris.MediaPlayer2.Player">
            <method name="Next"/>
            <method name="Previous"/>
            <method name="Pause"/>
            <method name="PlayPause"/>
            <method name="Stop"/>
            <method name="Play"/>
            <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
            <property name="PlaybackStatus" type="s" access="read"/>
            <property name="LoopStatus" type="s" access="readwrite"/>
            <property name="Rate" type="d" access="read"/>
            <property name="Metadata" type="a{sv}" access="read"/>
            <property name="Position" type="x" access="read"/>
            <property name="MinimumRate" type="d" access="read"/>
            <property name="MaximumRate" type="d" access="read"/>
            <property name="CanGoNext" type="b" access="read"/>
            <property name="CanGoPrevious" type="b" access="read"/>
            <property name="CanPlay" type="b" access="read"/>
            <property name="CanPause" type="b" access="read"/>
            <property name="CanSeek" type="b" access="read"/>
            <property name="CanControl" type="b" access="read"/>
          </interface>
        </node>
      XML

      REPEAT_MODE_TO_LOOP_STATUS = {
        consecutive: "None",
        repeat_one:  "Track",
        repeat_all:  "Playlist",
      }.freeze

      LOOP_STATUS_TO_REPEAT_MODE = REPEAT_MODE_TO_LOOP_STATUS.invert.freeze

      def initialize(sender)
        @sender = sender
        @song = nil
        @playback_state = :stopped
        @repeat_mode = :consecutive
        @position = 0
        register
      end

      def set_playback_state(state)
        @playback_state = state
        notify_player_properties("PlaybackStatus" => string_variant(playback_status))
      end

      def set_song(song)
        @song = song
        notify_player_properties("Metadata" => metadata_variant)
      end

      def set_position(position, notify)
        @position = position
        if notify
          emit_seeked(position)
        end
      end

      def set_repeat_mode(mode)
        @repeat_mode = mode
        notify_player_properties("LoopStatus" => string_variant(loop_status))
      end

      private

        def register
          @connection = Gio.bus_get_sync(Gio::BusType::SESSION, nil)
          request_name
          register_root_object
          register_player_object
        rescue GLib::Error => e
          warn("Unable to start the MPRIS server: #{e.message}")
          @connection = nil
        end

        def request_name
          name_arguments = GLib::Variant.parse(
            "(\"#{bus_name}\", uint32 #{REQUEST_NAME_DO_NOT_QUEUE})",
            "(su)",
          )
          @connection.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            name_arguments,
            GLib::VariantType.new("(u)"),
            Gio::DBusCallFlags::NONE,
            -1,
            nil,
          )
        end

        def bus_name = "org.mpris.MediaPlayer2.#{Config.settings_id.split(".").last.downcase}"

        def register_root_object
          interface = Gio::DBusNodeInfo.new(ROOT_XML).lookup_interface(ROOT_INTERFACE)
          @connection.register_object(
            OBJECT_PATH,
            interface,
            method(:handle_root_call),
            method(:get_root_property),
            method(:set_root_property),
          )
        end

        def register_player_object
          interface = Gio::DBusNodeInfo.new(PLAYER_XML).lookup_interface(PLAYER_INTERFACE)
          @connection.register_object(
            OBJECT_PATH,
            interface,
            method(:handle_player_call),
            method(:get_player_property),
            method(:set_player_property),
          )
        end

        def handle_root_call(_connection, _sender, _object_path, _interface_name, method_name, _parameters, invocation)
          case method_name
          when "Raise" then @sender.call(:raise)
          when "Quit" then nil
          end
          invocation.return_value(nil)
        end

        def get_root_property(_connection, _sender, _object_path, _interface_name, property_name)
          case property_name
          when "CanQuit" then bool_variant(false)
          when "CanRaise" then bool_variant(true)
          when "HasTrackList" then bool_variant(false)
          when "Identity" then string_variant("Amberol")
          when "DesktopEntry" then string_variant(Config.settings_id)
          when "SupportedUriSchemes" then GLib::Variant.new([], "as")
          when "SupportedMimeTypes" then GLib::Variant.new([], "as")
          end
        end

        def set_root_property(_connection, _sender, _object_path, _interface_name, _property_name, _value) = false

        # Upstream's connect_play_pause: paused resumes, stopped stays
        # stopped, anything else (playing) pauses.
        def play_pause_action
          case @playback_state
          when :paused then :play
          when :stopped then :stop
          else :pause
          end
        end

        def handle_player_call(_connection, _sender, _object_path, _interface_name, method_name, parameters, invocation)
          case method_name
          when "Next" then @sender.call(:skip_next)
          when "Previous" then @sender.call(:skip_previous)
          when "Pause" then @sender.call(:pause)
          when "PlayPause" then @sender.call(play_pause_action)
          when "Stop" then @sender.call(:stop)
          when "Play" then @sender.call(:play)
          when "Seek" then @sender.call(:seek, parameters[0] / 1_000_000)
          end
          invocation.return_value(nil)
        end

        def get_player_property(_connection, _sender, _object_path, _interface_name, property_name)
          case property_name
          when "PlaybackStatus" then string_variant(playback_status)
          when "LoopStatus" then string_variant(loop_status)
          when "Rate", "MinimumRate", "MaximumRate" then GLib::Variant.new(1.0, "d")
          when "Metadata" then metadata_variant
          when "Position" then GLib::Variant.new(@position * 1_000_000, "x")
          when "CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek", "CanControl"
            bool_variant(true)
          end
        end

        def set_player_property(_connection, _sender, _object_path, _interface_name, property_name, value)
          if property_name == "LoopStatus"
            @sender.call(:repeat, LOOP_STATUS_TO_REPEAT_MODE.fetch(value, :consecutive))
            true
          else
            false
          end
        end

        def playback_status
          case @playback_state
          when :playing then "Playing"
          when :paused then "Paused"
          else "Stopped"
          end
        end

        def loop_status = REPEAT_MODE_TO_LOOP_STATUS.fetch(@repeat_mode, "None")

        def bool_variant(value) = GLib::Variant.new(value, "b")

        def string_variant(value) = GLib::Variant.new(value.to_s, "s")

        # The track id has to be a syntactically valid object path, so
        # anything that is not [A-Za-z0-9_] in the uuid is folded to '_'.
        def track_id(song)
          uuid = song.uuid.to_s.gsub(/[^A-Za-z0-9_]/, "_")
          uuid.empty? ? "/org/mpris/MediaPlayer2/TrackList/NoTrack" : "/org/rubygtkproject/Amberol/Track/#{uuid}"
        end

        def metadata_variant
          song = @song
          if song.nil? || !song.valid?
            GLib::Variant.parse("{}", "a{sv}")
          else
            GLib::Variant.parse(metadata_text(song), "a{sv}")
          end
        end

        def metadata_text(song)
          entries = [
            dict_entry("mpris:trackid", GLib::Variant.new(track_id(song), "o")),
            dict_entry("mpris:length", GLib::Variant.new(song.duration * 1_000_000, "x")),
            dict_entry("xesam:title", GLib::Variant.new(song.title, "s")),
            dict_entry("xesam:artist", GLib::Variant.new([song.artist], "as")),
            dict_entry("xesam:album", GLib::Variant.new(song.album, "s")),
          ]
          cover_cache = song.cover_cache
          unless cover_cache.nil?
            entries << dict_entry("mpris:artUrl", GLib::Variant.new(Gio::File.new_for_path(cover_cache).uri.to_s, "s"))
          end
          "{#{entries.join(", ")}}"
        end

        def dict_entry(key, variant) = "#{GLib::Variant.new(key, "s").to_s(type_annotate: true)}: <#{variant.to_s(type_annotate: true)}>"

        def notify_player_properties(properties)
          unless @connection.nil?
            entries = properties.map { |name, variant| dict_entry(name, variant) }
            payload = GLib::Variant.parse(
              "(#{GLib::Variant.new(PLAYER_INTERFACE, "s").to_s(type_annotate: true)}, {#{entries.join(", ")}}, @as [])",
              "(sa{sv}as)",
            )
            @connection.emit_signal(
              nil,
              OBJECT_PATH,
              PROPERTIES_INTERFACE,
              "PropertiesChanged",
              payload,
            )
          end
        end

        def emit_seeked(position)
          unless @connection.nil?
            @connection.emit_signal(
              nil,
              OBJECT_PATH,
              PLAYER_INTERFACE,
              "Seeked",
              GLib::Variant.parse("(#{position * 1_000_000},)", "(x)"),
            )
          end
        end
    end
  end
end
