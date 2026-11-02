# frozen_string_literal: true

require "adwaita"
require_relative "config"
require_relative "i18n"

module Amberol
  # The about dialog.
  #
  # Ported from Application::show_about in upstream's src/application.rs: the
  # same fields, the same GPL-3.0 licence, and the translator-credits msgid
  # translators replace with their names.
  #
  # AdwAboutDialog is a final type, so this configures one rather than
  # subclassing it.
  module AboutDialog
    def self.build
      Adwaita::AboutDialog.new.tap do |dialog|
        dialog.application_icon = Config::APPLICATION_ID
        dialog.application_name = "Amberol"
        dialog.developer_name = "Emmanuele Bassi"
        dialog.version = Config::VERSION
        dialog.developers = ["Emmanuele Bassi"]
        dialog.copyright = "© 2022 Emmanuele Bassi"
        dialog.website = "https://apps.gnome.org/Amberol/"
        dialog.issue_url = "https://gitlab.gnome.org/World/amberol/-/issues/new"
        dialog.license_type = Gtk::License::GPL_3_0
        # Translators: Replace "translator-credits" with your names, one name per line
        dialog.translator_credits = I18n.i18n("translator-credits")
      end
    end
  end
end
