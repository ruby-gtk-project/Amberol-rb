# frozen_string_literal: true

require "spec_helper"
require "amberol/i18n"

# Ported from upstream's src/i18n.rs `mod tests`: test_i18n, test_i18n_f,
# test_i18n_k and test_pi18n. Upstream's gettext/ngettext/pgettext/npgettext
# calls look up msgids in a compiled catalogue that has no "translate1" or
# similar test string, so they fall through to the msgid (or, for the plural
# forms, to the Germanic/English singular/plural rule) exactly the way
# Amberol::I18n does when no .mo catalogue is bound — which is the behaviour
# these tests pin down, not any specific translation.
RSpec.describe Amberol::I18n do
  describe "i18n/ni18n (test_i18n)" do
    it "returns the msgid untranslated" do
      expect(described_class.i18n("translate1")).to eq("translate1")
    end

    it "picks the singular or plural form by count" do
      expect(described_class.ni18n("translate1", "translate multi", 1)).to eq("translate1")
      expect(described_class.ni18n("translate1", "translate multi", 2)).to eq("translate multi")
    end
  end

  describe "i18n_f/ni18n_f (test_i18n_f)" do
    it "substitutes a single leading placeholder" do
      expect(described_class.i18n_f("{} param", ["one"])).to eq("one param")
    end

    it "substitutes a single middle placeholder" do
      expect(described_class.i18n_f("middle {} param", ["one"])).to eq("middle one param")
    end

    it "substitutes a single trailing placeholder" do
      expect(described_class.i18n_f("end {}", ["one"])).to eq("end one")
    end

    it "substitutes multiple placeholders in order" do
      expect(described_class.i18n_f("multiple {} and {}", ["one", "two"])).to eq("multiple one and two")
    end

    it "substitutes placeholders in the plural form chosen by count" do
      expect(
        described_class.ni18n_f("singular {} and {}", "plural {} and {}", 2, ["one", "two"]),
      ).to eq("plural one and two")
      expect(
        described_class.ni18n_f("singular {} and {}", "plural {} and {}", 1, ["one", "two"]),
      ).to eq("singular one and two")
    end
  end

  describe "i18n_k/ni18n_k (test_i18n_k)" do
    it "substitutes a single leading keyword" do
      expect(described_class.i18n_k("{one} param", {"one" => "one"})).to eq("one param")
    end

    it "substitutes a single middle keyword" do
      expect(described_class.i18n_k("middle {one} param", {"one" => "one"})).to eq("middle one param")
    end

    it "substitutes a single trailing keyword" do
      expect(described_class.i18n_k("end {one}", {"one" => "one"})).to eq("end one")
    end

    it "substitutes multiple keywords regardless of declaration order" do
      kwargs = {"one" => "1", "two" => "two"}
      expect(described_class.i18n_k("multiple {one} and {two}", kwargs)).to eq("multiple 1 and two")
      expect(described_class.i18n_k("multiple {two} and {one}", kwargs)).to eq("multiple two and 1")
    end

    it "substitutes a repeated keyword every time it appears" do
      kwargs = {"one" => "1", "two" => "two"}
      expect(described_class.i18n_k("multiple {one} and {one}", kwargs)).to eq("multiple 1 and 1")
    end

    it "substitutes keywords in the plural form chosen by count" do
      kwargs = {"one" => "1", "two" => "two"}
      expect(
        described_class.ni18n_k("singular {one} and {two}", "plural {one} and {two}", 1, kwargs),
      ).to eq("singular 1 and two")
      expect(
        described_class.ni18n_k("singular {one} and {two}", "plural {one} and {two}", 2, kwargs),
      ).to eq("plural 1 and two")
    end
  end

  describe "pi18n/pni18n/pi18n_f/pi18n_k (test_pi18n)" do
    it "returns the msgid untranslated regardless of context" do
      expect(described_class.pi18n("This is the context", "translate1")).to eq("translate1")
    end

    it "picks the singular or plural form by count, regardless of context" do
      expect(described_class.pni18n("context", "translate1", "translate multi", 1)).to eq("translate1")
      expect(
        described_class.pni18n("The context string", "translate1", "translate multi", 2),
      ).to eq("translate multi")
    end

    it "substitutes positional placeholders under a context" do
      expect(described_class.pi18n_f("Context for translation", "{} param", ["one"])).to eq("one param")
    end

    it "substitutes keyword placeholders under a context" do
      expect(described_class.pi18n_k("context", "{one} param", {"one" => "one"})).to eq("one param")
    end
  end
end
