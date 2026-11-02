# frozen_string_literal: true

require "adwaita"
require_relative "i18n"

module Amberol
  # The keyboard shortcuts dialog.
  #
  # Ported from upstream's src/gtk/shortcuts-dialog.blp: the same three
  # sections in the same order, with the same items.
  #
  # Upstream lets Adw.ShortcutsItem look an accelerator up from the action
  # name; the Ruby bindings require both the title and the accelerator at
  # construction, so each item carries the accelerator the application binds
  # to that action in Application#setup_accelerators.
  #
  # AdwShortcutsDialog is a final type, so this configures one rather than
  # subclassing it.
  class ShortcutsDialog
    def self.sections
      [
        [
          I18n.pi18n("shortcut window", "General"),
          [
            [I18n.pi18n("shortcut window", "Toggle primary menu"), "F10"],
            [I18n.pi18n("shortcut window", "Copy song details to the clipboard"), "<primary>c"],
            [I18n.pi18n("shortcut window", "Show shortcuts"), "<primary>question"],
            [I18n.pi18n("shortcut window", "Quit"), "<primary>q"],
          ],
        ],
        [
          I18n.pi18n("shortcut window", "Playlist"),
          [
            [I18n.pi18n("shortcut window", "Add a song to the playlist"), "<primary>s"],
            [I18n.pi18n("shortcut window", "Add a folder to the playlist"), "<primary>a"],
            [I18n.pi18n("shortcut window", "Clear the playlist"), "<primary><shift>l"],
            [I18n.pi18n("shortcut window", "Toggle the playlist pane"), "F9"],
            [I18n.pi18n("shortcut window", "Search the playlist"), "<primary><shift>f"],
            [I18n.pi18n("shortcut window", "Toggle shuffling songs"), "<primary>r"],
          ],
        ],
        [
          I18n.pi18n("shortcut window", "Playback"),
          [
            [I18n.pi18n("shortcut window", "Toggle play/pause"), "<primary>p"],
            [I18n.pi18n("shortcut window", "Previous song"), "<primary>b"],
            [I18n.pi18n("shortcut window", "Next song"), "<primary>n"],
            [I18n.pi18n("shortcut window", "Seek backwards in the current song"), "<primary>Left"],
            [I18n.pi18n("shortcut window", "Seek forward in the current song"), "<primary>Right"],
          ],
        ],
      ]
    end

    def build
      dialog.tap do |widget|
        self.class.sections.each do |(title, items)|
          widget.add(section(title, items))
        end
      end
    end

    def dialog
      @dialog ||= Adwaita::ShortcutsDialog.new.tap do |widget|
        widget.title = I18n.i18n("Keyboard Shortcuts")
      end
    end

    private

      def section(title, items)
        Adwaita::ShortcutsSection.new.tap do |section|
          section.title = title
          items.each { |(label, accelerator)| section.add(item(label, accelerator)) }
        end
      end

      # Positional, not keyword, arguments — even though the error a
      # no-argument `new` raises advertises them as "title:" and
      # "accelerator:".
      def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
  end
end
