# frozen_string_literal: true

require_relative "rb/version"

# The part of Amberol that loads without a display.
#
# `require "gtk4"` initialises GTK at require time and raises Gtk::InitError
# when there is no display server, so anything that reaches a widget class
# cannot be loaded by a plain `ruby -e` or by a test process on a headless
# machine. This file is where the gem's version constant lives, which is why
# spec/spec_helper.rb requires it: specs for the display-free half need
# nothing more, and the ones that drive widgets ask for "amberol" themselves.
