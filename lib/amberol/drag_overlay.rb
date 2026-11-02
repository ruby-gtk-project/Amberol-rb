# frozen_string_literal: true

require "adwaita"

module Amberol
  # The "drop a song here" overlay.
  #
  # Ported from upstream's src/drag_overlay.rs: an overlay whose revealer
  # crossfades a status page in while a drag is over the window, and blurs the
  # content underneath it.
  class DragOverlay < Adwaita::Bin
    type_register

    def initialize(title = nil)
      super()
      @drop_target = nil
      @drop_handler = nil
      add_css_class("dragoverlay")
      self.child = overlay
      overlay.add_overlay(revealer)
      revealer.child = status
      unless title.nil?
        self.title = title
      end
    end

    def title = status.title

    def title=(title)
      status.title = title.to_s
      title
    end

    # The widget the overlay covers.
    def content = overlay.child

    def content=(widget)
      overlay.child = widget
      widget
    end

    def drop_target = @drop_target

    # Replaces the drop target, disconnecting the old one's handler first —
    # upstream's DragOverlay::set_drop_target.
    def drop_target=(drop_target)
      unless @drop_target.nil?
        remove_controller(@drop_target)
        unless @drop_handler.nil?
          @drop_target.signal_handler_disconnect(@drop_handler)
        end
      end

      @drop_handler = drop_target.signal_connect("notify::current-drop") do |target, _param|
        reveal(!target.current_drop.nil?)
      end

      add_controller(drop_target)
      @drop_target = drop_target
      drop_target
    end

    def overlay = @overlay ||= Gtk::Overlay.new

    def revealer
      @revealer ||= Gtk::Revealer.new.tap do |widget|
        widget.can_target = false
        widget.transition_type = :crossfade
        widget.reveal_child = false
      end
    end

    def status
      @status ||= Adwaita::StatusPage.new.tap do |page|
        page.icon_name = "folder-music-symbolic"
        page.add_css_class("drag-overlay-status-page")
      end
    end

    private

      def reveal(revealed)
        revealer.reveal_child = revealed
        overlay.child.then do |child|
          unless child.nil?
            if revealed
              child.add_css_class("blurred")
            else
              child.remove_css_class("blurred")
            end
          end
        end
      end
  end
end
