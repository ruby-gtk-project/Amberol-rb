# frozen_string_literal: true

require_relative "rb/version"

module Amberol
  # Build-time configuration.
  #
  # Ported from upstream's src/config.rs.in, which meson fills in at configure
  # time with the application id, the gettext package, the locale and data
  # directories, the version and the build profile. A Ruby checkout has no
  # configure step, so the same values are resolved relative to this file, and
  # the profile comes from the environment instead of a meson option.
  module Config
    # Upstream ships io.bassi.Amberol; the port keeps its own id so both can be
    # installed side by side.
    BASE_APPLICATION_ID = "org.rubygtkproject.Amberol"

    # "development" is upstream's devel profile, which suffixes the id with
    # ".Devel" and makes the window wear the "devel" style class.
    PROFILE = ENV.fetch("AMBEROL_PROFILE", "default")

    APPLICATION_ID = "#{BASE_APPLICATION_ID}#{PROFILE == "development" ? ".Devel" : ""}"

    VERSION = Amberol::Rb::Version::VERSION

    GETTEXT_PACKAGE = "amberol"

    # The checkout's own data/ and po/ directories: this is PKGDATADIR and
    # LOCALEDIR for a port that runs straight from its source tree.
    PKGDATADIR = File.expand_path("../../data", __dir__)
    LOCALEDIR = File.expand_path("../../po", __dir__)

    def self.devel? = APPLICATION_ID.end_with?(".Devel")

    # The id the GSettings schema and the cover cache are keyed on: upstream
    # ships a single schema for both profiles, so the ".Devel" suffix is
    # trimmed off (src/utils.rs, settings_manager).
    def self.settings_id = APPLICATION_ID.delete_suffix(".Devel")
  end
end
