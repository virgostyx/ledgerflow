require "rails_helper"

RSpec.describe Agent::Citations do
  let(:known) { Set.new([ "R04:2026-09-30:customer:total", "entry:12", "calc:ab12cd34ef56" ]) }

  describe ".resolve" do
    it "numbers the sources in order of appearance, one number for a source cited twice" do
      text, citations, invalid = described_class.resolve("Total [[ref:R04:2026-09-30:customer:total]], entry [[ref:entry:12]], again [[ref:R04:2026-09-30:customer:total]].", known)

      expect(citations.map { |c| [ c["n"], c["ref"] ] }).to eq([ [ 1, "R04:2026-09-30:customer:total" ], [ 2, "entry:12" ] ])
      expect(citations.first["label"]).to eq("Aged balance (customers) as of 2026-09-30, total")
      expect(invalid).to be_empty
      expect(text).to include("[[ref:entry:12]]")
    end

    it "replaces a source nobody gave, and says which, whatever it looks like" do
      text, citations, invalid = described_class.resolve("See [[ref:entry:999]] and [[ref:evil:1]] and [[ref:http://evil.example]].", known)

      expect(text).to eq("See [unverified source] and [unverified source] and [[ref:http://evil.example]].").or eq("See [unverified source] and [unverified source] and [unverified source].")
      expect(citations).to be_empty
      expect(invalid).to include("entry:999", "evil:1")
    end

    it "does not accept a reference that the table does not know how to open, even if a tool gave it" do
      _, citations, invalid = described_class.resolve("x [[ref:weird:1]]", Set.new([ "weird:1" ]))

      expect(citations).to be_empty
      expect(invalid).to eq([ "weird:1" ])
    end

    it "accepts a calculation, which opens no screen, and says so" do
      _, citations, = described_class.resolve("Net [[ref:calc:ab12cd34ef56]]", known)

      expect(citations).to eq([ { "n" => 1, "ref" => "calc:ab12cd34ef56", "label" => "Calculation", "computed" => true } ])
    end

    it "leaves a text with no marker as it is" do
      expect(described_class.resolve("Nothing to cite.", known)).to eq([ "Nothing to cite.", [], [] ])
    end
  end

  describe ".render" do
    let(:citations) { [ { "n" => 1, "ref" => "entry:12", "label" => "Entry #12", "computed" => false }, { "n" => 2, "ref" => "calc:ab12cd34ef56", "label" => "Calculation", "computed" => true } ] }

    it "turns a marker into a link built by the application, to the screen of the source, with its label on hover" do
      html = described_class.render("<p>Entry [[ref:entry:12]].</p>", citations)

      expect(html).to include('<a href="/accounting/journal_entries/12" title="[1] Entry #12"', ">[1]</a>")
    end

    it "turns a calculation into a number with no link" do
      html = described_class.render("<p>Net [[ref:calc:ab12cd34ef56]]</p>", citations)

      expect(html).to include("<sup title=\"[2] Calculation (calculated)\">[2]</sup>")
      expect(html).not_to include("href")
    end

    it "shows a marker that was never resolved as an unverified source, never as a link" do
      expect(described_class.render("<p>[[ref:entry:999]]</p>", citations)).to eq("<p>#{described_class::UNVERIFIED}</p>")
    end
  end
end
