# frozen_string_literal: true

require "gtk4"
require_relative "../i18n"
require_relative "controller"

module Amberol
  module Audio
    # Keeps the session awake while a song is playing.
    #
    # Ported from upstream's src/audio/inhibit_controller.rs: it takes an
    # inhibit cookie from the application when playback starts and gives it
    # back when playback stops or pauses.
    class InhibitController
      include Controller

      def initialize
        @cookie = 0
      end

      def set_playback_state(state)
        if state == :playing
          inhibit
        else
          uninhibit
        end
      end

      private

        def inhibit
          application.then do |app|
            if !app.nil? && @cookie.zero?
              @cookie = app.inhibit(app.active_window, :suspend, I18n.i18n("Playback in progress"))
            end
          end
        end

        def uninhibit
          application.then do |app|
            unless app.nil? || @cookie.zero?
              app.uninhibit(@cookie)
              @cookie = 0
            end
          end
        end

        def application = Gio::Application.default
    end
  end
end
