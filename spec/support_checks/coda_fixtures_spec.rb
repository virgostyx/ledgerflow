require "rails_helper"

# The CODA files of F02 are fictitious and built from the Febelfin layout as understood by the author (see
# spec/support/coda_builder.rb). This spec checks that they are what they claim to be, so that a failing parser spec
# points at the parser and not at a malformed fixture. It says nothing about what real banks send.
RSpec.describe "CODA fixtures" do
  DIR = Rails.root.join("spec/fixtures/files/coda")

  VALID = %w[simple two_accounts accents_latin1 accents_cp850 detailed_movement chain_a chain_b_continues chain_b_break overlap_a overlap_b
             integrity_mismatch invalid_structured usd_account].freeze

  def read(name, encoding: nil)
    bytes = File.binread(DIR.join("#{name}.cod"))
    text = encoding ? bytes.force_encoding(encoding).encode("UTF-8") : bytes.force_encoding("ISO-8859-1").encode("UTF-8")
    text.split("\r\n")
  end

  def amount(line, from) = BigDecimal(line[from, 15]) / 1000

  def signed(line, sign_at, from) = line[sign_at] == "1" ? -amount(line, from) : amount(line, from)

  VALID.each do |name|
    describe name do
      let(:lines) { read(name, encoding: name.include?("cp850") ? "CP850" : nil) }

      it "has records of exactly 128 characters, a header first and a trailer last" do
        expect(lines.map(&:length).uniq).to eq([ 128 ])
        expect(lines.first[0]).to eq("0")
        expect(lines.last[0]).to eq("9")
      end

      it "only holds known record types, in an order the specification allows" do
        expect(lines.map { |l| l[0] }.uniq - %w[0 1 2 3 4 8 9]).to be_empty
        lines.each_cons(2) { |a, b| expect(%w[0 8].include?(a[0]) ? %w[1 9] : %w[1 2 3 4 8]).to include(b[0]) }
      end

      it "counts its records and totals its movements in the trailer" do
        trailer = lines.last
        expect(trailer[16, 6].to_i).to eq(lines.count { |l| l[0] =~ /[1-8]/ })
        movements = lines.select { |l| l.start_with?("21") }
        expect(amount(trailer, 22)).to eq(movements.select { |l| l[31] == "1" }.sum { |l| amount(l, 32) })
        expect(amount(trailer, 37)).to eq(movements.select { |l| l[31] == "0" }.sum { |l| amount(l, 32) })
      end

      it "carries IBANs whose check digits are valid" do
        lines.grep(/\A1/).each do |old|
          iban = old[5, 34].strip
          next unless iban.start_with?("BE")

          digits = "#{iban[4..]}#{iban[0, 4]}".gsub(/[A-Z]/) { |c| (c.ord - 55).to_s }
          expect(digits.to_i % 97).to eq(1)
        end
      end
    end
  end

  (VALID - %w[integrity_mismatch]).each do |name|
    it "#{name}: old balance plus the movements equals the new balance, statement by statement" do
      lines = read(name, encoding: name.include?("cp850") ? "CP850" : nil)
      lines.slice_when { |_, b| b.start_with?("1") }.each do |statement|
        next unless statement.first.start_with?("1")

        movements = statement.select { |l| l.start_with?("21") }.sum { |l| signed(l, 31, 32) }
        expect(signed(statement.first, 42, 43) + movements).to eq(signed(statement.find { |l| l.start_with?("8") }, 41, 42))
      end
    end
  end

  it "integrity_mismatch: does not add up, on purpose" do
    lines = read("integrity_mismatch")
    movements = lines.select { |l| l.start_with?("21") }.sum { |l| signed(l, 31, 32) }

    expect(signed(lines[1], 42, 43) + movements).not_to eq(signed(lines.find { |l| l.start_with?("8") }, 41, 42))
  end

  it "two_accounts: holds two statements for two accounts" do
    expect(read("two_accounts").grep(/\A1/).map { |l| l[5, 34].strip }.uniq.size).to eq(2)
  end

  it "structured communications: valid in simple, with wrong check digits in invalid_structured" do
    ok  = read("simple").grep(/\A21/).filter_map { |l| l[62, 15][3, 12] if l[61] == "1" }
    bad = read("invalid_structured").grep(/\A21/).filter_map { |l| l[62, 15][3, 12] if l[61] == "1" }

    expect(ok).to all(satisfy { |digits| Accounting::StructuredCommunication.valid?(digits) })
    expect(bad).to all(satisfy { |digits| !Accounting::StructuredCommunication.valid?(digits) })
  end

  it "detailed_movement: carries 2.2, 2.3, 3.1, 3.2 and a free message after its 2.1" do
    expect(read("detailed_movement").map { |l| l[0, 2].strip }).to include("21", "22", "23", "31", "4")
  end

  it "chain: the second statement opens on the first one's closing balance, except in chain_b_break" do
    closing = signed(read("chain_a").find { |l| l.start_with?("8") }, 41, 42)

    expect(signed(read("chain_b_continues")[1], 42, 43)).to eq(closing)
    expect(signed(read("chain_b_break")[1], 42, 43)).not_to eq(closing)
  end

  it "overlap: the second statement repeats the movements of the first, and adds one" do
    references = ->(name) { read(name).grep(/\A21/).map { |l| l[10, 21] } }

    expect(references.("overlap_b") & references.("overlap_a")).to eq(references.("overlap_a"))
    expect(references.("overlap_b").size).to eq(references.("overlap_a").size + 1)
  end

  it "accents: the two files hold the same text, in two encodings" do
    latin = File.binread(DIR.join("accents_latin1.cod"))
    cp850 = File.binread(DIR.join("accents_cp850.cod"))

    expect(latin).not_to eq(cp850)
    expect(read("accents_latin1").join).to eq(read("accents_cp850", encoding: "CP850").join)
    expect(read("accents_latin1").join).to include("SOCIÉTÉ ACME", "ÉCOLE DES BEAUX-ARTS")
  end

  it "usd_account: is in dollars" do
    expect(read("usd_account")[1][39, 3]).to eq("USD")
  end

  describe "the files made to be refused" do
    it "broken_length has a record that is not 128 characters" do
      expect(read("broken_length").map(&:length).uniq).to include(130)
    end

    it "truncated has no trailer" do
      expect(read("truncated").last[0]).not_to eq("9")
    end

    it "unknown_record has a record of an unknown type" do
      expect(read("unknown_record").map { |l| l[0] }).to include("7")
    end

    it "not_coda is plain text" do
      expect(read("not_coda").first).to start_with("this is not")
    end
  end
end
