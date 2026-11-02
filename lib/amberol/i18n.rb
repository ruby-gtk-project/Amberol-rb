# frozen_string_literal: true

require_relative "config"

module Amberol
  # Translation helpers.
  #
  # Ported from upstream's src/i18n.rs: the same twelve entry points, with the
  # same "{}" positional and "{name}" keyword substitution applied *after* the
  # catalogue lookup, so a translator can reorder the placeholders.
  #
  # Upstream calls gettextrs; here the lookup goes through ruby-gettext when
  # that gem is installed and a catalogue directory exists, and returns the
  # msgid otherwise — which is exactly what gettext itself does for a locale it
  # has no catalogue for.
  module I18n
    class << self
      # --- Simple translations ------------------------------------------

      def i18n(format) = gettext(format)

      def i18n_f(format, args) = freplace(gettext(format), args)

      def i18n_k(format, kwargs) = kreplace(gettext(format), kwargs)

      # --- Singular and plural ------------------------------------------

      def ni18n(single, multiple, number) = ngettext(single, multiple, number)

      def ni18n_f(single, multiple, number, args)
        freplace(ngettext(single, multiple, number), args)
      end

      def ni18n_k(single, multiple, number, kwargs)
        kreplace(ngettext(single, multiple, number), kwargs)
      end

      # --- Translations with a context ----------------------------------

      def pi18n(ctx, format) = pgettext(ctx, format)

      def pi18n_f(ctx, format, args) = freplace(pgettext(ctx, format), args)

      def pi18n_k(ctx, format, kwargs) = kreplace(pgettext(ctx, format), kwargs)

      # --- Plural with a context ----------------------------------------

      def pni18n(ctx, single, multiple, number)
        npgettext(
          ctx,
          single,
          multiple,
          number,
        )
      end

      def pni18n_f(ctx, single, multiple, number, args)
        freplace(
          npgettext(
            ctx,
            single,
            multiple,
            number,
          ),
          args,
        )
      end

      def pni18n_k(ctx, single, multiple, number, kwargs)
        kreplace(
          npgettext(
            ctx,
            single,
            multiple,
            number,
          ),
          kwargs,
        )
      end

      # Whether a catalogue backend is in play. The app binds the text domain
      # once at startup; everything else goes through the helpers above.
      def bind_text_domain
        @bound = false
        if catalogue?
          begin
            backend.bindtextdomain(Config::GETTEXT_PACKAGE, path: Config::LOCALEDIR)
            @bound = true
          rescue LoadError
            @bound = false
          end
        end
        @bound
      end

      def bound? = @bound == true

      private

        # Replaces each "{}" in turn with the next argument, leaving a "{}"
        # with no argument alone — upstream's freplace, which zips the split
        # parts against the arguments and stops at the shorter of the two.
        def freplace(input, args)
          input.split("{}", -1).then do |parts|
            parts.first.dup.tap do |output|
              parts.drop(1).each_with_index do |part, index|
                args[index].then do |arg|
                  unless arg.nil?
                    output << arg.to_s << part
                  end
                end
              end
            end
          end
        end

        # Replaces every "{name}" with its value — upstream's kreplace.
        def kreplace(input, kwargs)
          kwargs.to_a.inject(input) do |text, (key, value)|
            text.gsub("{#{key}}", value.to_s)
          end
        end

        def gettext(msgid)
          bound?.then do |available|
            available ? backend.gettext(msgid) : msgid
          end
        end

        def ngettext(single, multiple, number)
          bound?.then do |available|
            available ? backend.ngettext(single, multiple, number) : plural(single, multiple, number)
          end
        end

        def pgettext(ctx, msgid)
          bound?.then do |available|
            available ? backend.pgettext(ctx, msgid) : msgid
          end
        end

        def npgettext(ctx, single, multiple, number)
          bound?.then do |available|
            available ? backend.npgettext(
              ctx,
              single,
              multiple,
              number,
            ) : plural(single, multiple, number)
          end
        end

        # The fallback plural rule: the Germanic/English one gettext assumes
        # for an untranslated msgid.
        def plural(single, multiple, number) = number == 1 ? single : multiple

        # ruby-gettext exposes its lookup as instance methods on the GetText
        # module, so the module gets mixed into a bare object rather than into
        # this one — nothing here should answer to `_` or `n_`.
        def backend
          @backend ||= begin
            require "gettext"
            Object.new.tap { |obj| obj.singleton_class.include(GetText) }
          end
        end

        # A catalogue directory with at least one compiled .mo file in it.
        # Without one there is nothing for the backend to look up, and loading
        # the gem would only cost startup time.
        def catalogue?
          Dir.exist?(Config::LOCALEDIR) &&
            !Dir.glob(File.join(Config::LOCALEDIR, "**", "#{Config::GETTEXT_PACKAGE}.mo")).empty?
        rescue LoadError
          false
        end
    end
  end
end
