require "rails_helper"
require Rails.root.join("tools/ledger-verify/lib/ledger_verify/canonical")

# B03c step 1: JSON canonicalisation, RFC 8785 (JCS). Vectors of the RFC (section 3.2.3 for the sorting, appendix B for the numbers) and of the ES6 rules it relies on.
RSpec.describe LedgerVerify::Canonical do
  def canon(value) = described_class.generate(value)

  describe "the example of the RFC (section 3.2.3)" do
    it "sorts the members by UTF-16 code units, writes numbers and strings in their canonical form" do
      input = {
        "numbers" => [ 333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001 ],
        "string" => "\u20ac$\u000F\n" + "A'B" + '"' + '\\' + '\\' + '"' + "/",
        "literals" => [ nil, true, false ]
      }

      expect(canon(input)).to eq('{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\u000f\nA\'B\"\\\\\\\\\"/"}')
    end

    it "sorts the keys of the example (RFC 8785 section 3.2.3: carriage return, digits, Unicode, emoji, surrogate pairs)" do
      input = { "€" => "Euro Sign", "\r" => "Carriage Return", "דּ" => "Hebrew Letter Dalet With Dagesh", "1" => "One", "\u{1F600}" => "Emoji: Grinning Face",
                "\u0080" => "Control", "ö" => "Latin Small Letter O With Diaeresis" }

      expect(JSON.parse(canon(input)).keys).to eq([ "\r", "1", "\u0080", "ö", "€", "\u{1F600}", "דּ" ])
      # the emoji (surrogates D83D DE00) sorts before U+FB33 in UTF-16 order, after U+20AC: the order of the RFC
    end
  end

  describe "numbers (ES6, as the RFC's appendix B)" do
    {
      0.0 => "0", -0.0 => "0", 5e-324 => "5e-324", 1.7976931348623157e308 => "1.7976931348623157e+308", 9007199254740992.0 => "9007199254740992",
      9007199254740994.0 => "9007199254740994", 295147905179352830000.0 => "295147905179352830000", 1e21 => "1e+21", 1e20 => "100000000000000000000",
      1e-6 => "0.000001", 1e-7 => "1e-7", 0.1 => "0.1", 100.0 => "100", 4.35 => "4.35", 1.5e300 => "1.5e+300", -12.5 => "-12.5"
    }.each do |number, text|
      it "writes #{number.inspect} as #{text}" do
        expect(canon(number)).to eq(text)
      end
    end

    it "writes integers as they are, and refuses what a double cannot hold exactly" do
      expect(canon(42)).to eq("42")
      expect(canon(-7)).to eq("-7")
      expect(canon(2**53 - 1)).to eq("9007199254740991")
      expect { canon(2**53) }.to raise_error(LedgerVerify::Canonical::Error, /integer/)
    end

    it "refuses NaN and infinity, and anything that is not JSON" do
      expect { canon(Float::NAN) }.to raise_error(LedgerVerify::Canonical::Error)
      expect { canon(Float::INFINITY) }.to raise_error(LedgerVerify::Canonical::Error)
      expect { canon(BigDecimal("1.5")) }.to raise_error(LedgerVerify::Canonical::Error, /string/) # decimals travel as strings
      expect { canon(Time.now) }.to raise_error(LedgerVerify::Canonical::Error)
    end
  end

  describe "strings" do
    it "escapes the quote, the backslash and the controls, and nothing else" do
      expect(canon("a\"b\\c\b\t\n\f\r\u0001\u001f")).to eq('"a\"b\\\\c\b\t\n\f\r\u0001\u001f"')
      expect(canon("é/\u007f€\u{1F600}")).to eq("\"é/\u007f€\u{1F600}\"")
    end

    it "refuses a string that is not valid UTF-8" do
      expect { canon("\xff".b.force_encoding("UTF-8")) }.to raise_error(LedgerVerify::Canonical::Error, /UTF-8/)
    end
  end

  describe "structures" do
    it "writes no space, symbol keys as strings, arrays in their order, and nested objects sorted" do
      expect(canon({ b: [ 1, { z: 1, a: 2 } ], a: nil })).to eq('{"a":null,"b":[1,{"a":2,"z":1}]}')
      expect(canon([])).to eq("[]")
      expect(canon({})).to eq("{}")
    end

    it "refuses two keys that are the same once written (a symbol and its string)" do
      expect { canon({ "a" => 1, a: 2 }) }.to raise_error(LedgerVerify::Canonical::Error, /duplicate/)
    end

    it "gives the same bytes whatever the order the keys were inserted in" do
      expect(canon({ "x" => 1, "y" => 2 })).to eq(canon({ "y" => 2, "x" => 1 }))
    end

    it "is encoded in UTF-8" do
      expect(canon({ "é" => "€" }).encoding).to eq(Encoding::UTF_8)
    end
  end
end
