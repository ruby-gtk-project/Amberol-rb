# frozen_string_literal: true

require "gtk4"
require_relative "i18n"

module Amberol
  # The menu behind the hamburger button.
  #
  # Ported from the `menu primary_menu` block at the end of upstream's
  # src/gtk/playback-control.blp: five sections, with the ReplayGain submenu
  # as the fourth.
  module PrimaryMenu
    # Each section is a list of [label, action, target]; a target of nil means
    # the action takes no parameter.
    def self.sections
      [
        [
          [I18n.i18n("Copy"), "win.copy", nil],
          [I18n.i18n("Open Directory"), "win.open-directory", nil],
        ],
        [
          [I18n.i18n("Add _Song"), "queue.add-song", nil],
          [I18n.i18n("Add _Folder"), "queue.add-folder", nil],
          [I18n.i18n("Clear"), "queue.clear", nil],
        ],
        [
          [I18n.i18n("_Match Cover Art"), "win.enable-recoloring", nil],
          [I18n.i18n("_Background Playback"), "app.background-play", nil],
        ],
        [],
        [
          [I18n.i18n("_Keyboard Shortcuts"), "app.shortcuts", nil],
          [I18n.i18n("_About Amberol"), "app.about", nil],
          [I18n.i18n("_Quit"), "app.quit", nil],
        ],
      ]
    end

    def self.replaygain_items
      [
        [I18n.pi18n("replaygain-menu", "_Album"), "win.replaygain", "album"],
        [I18n.pi18n("replaygain-menu", "_Song"), "win.replaygain", "track"],
        [I18n.pi18n("replaygain-menu", "_Disabled"), "win.replaygain", "off"],
      ]
    end

    def self.build
      Gio::Menu.new.tap do |menu|
        sections.each do |items|
          if items.empty?
            menu.append_section(nil, replaygain_section)
          else
            menu.append_section(nil, section(items))
          end
        end
      end
    end

    def self.section(items)
      Gio::Menu.new.tap do |menu|
        items.each { |(label, action, target)| menu.append_item(item(label, action, target)) }
      end
    end

    def self.replaygain_section
      Gio::Menu.new.tap do |menu|
        menu.append_submenu(I18n.i18n("_ReplayGain"), section(replaygain_items))
      end
    end

    def self.item(label, action, target)
      Gio::MenuItem.new(label, nil).tap do |menu_item|
        if target.nil?
          menu_item.set_detailed_action(action)
        else
          menu_item.set_action_and_target_value(action, GLib::Variant.new(target))
        end
      end
    end
  end
end
