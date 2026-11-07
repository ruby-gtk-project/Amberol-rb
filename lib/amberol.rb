# frozen_string_literal: true

require_relative "amberol/config"

# Ported from upstream's src/main.rs: before anything else loads, main() sets
# the PulseAudio stream properties so the Sound panel's mixer labels the
# running process as "Amberol" with a music role and the app's icon, rather
# than falling back to the executable name.
ENV["PULSE_PROP_application.icon_name"] = Amberol::Config::APPLICATION_ID
ENV["PULSE_PROP_application.metadata().name"] = "Amberol"
ENV["PULSE_PROP_media.role"] = "music"

require_relative "amberol/application"
