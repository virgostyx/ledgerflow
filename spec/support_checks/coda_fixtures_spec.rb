require "rails_helper"

# The CODA files of F02 are fictitious, built from the Febelfin CODA specification v2.8 (annex I, docs/dev/features/) by
# spec/support/coda_builder.rb. This spec checks that they are what they claim to be, so that a failing parser spec points at
# the parser and not at a malformed fixture. It says nothing about the habits of real banks.
RSpec.describe "CODA fixtures" do
  FIXTURE_DIR = Rails.root.join("spec/fixtures/files/coda")

  VALID = %w[simple two_accounts accents_latin1 accents_cp850 detailed_movement chain_a chain_b_continues chain_b_break overlap_a overlap_b
             integrity_mismatch invalid_structured usd_account empty_account].freeze

  def read(name)
    bytes = File.binread(FIXTURE_DIR.join("#{name}.cod"))
    text = bytes.force_encoding(name.include?("cp850") ? "CP850" : "ISO-8859-1").encode("UTF-8")
    text.split("\r\n")
  end

  # a physical file holds one logical file (0 ... 9) per account
  def logical_files(lines) = lines.slice_before { |l| l.start_with?("0") }.to_a

  def amount(line, from) = BigDecimal(line[from, 15]) / 1000
  def signed(line, sign_at, from) = line[sign_at] == "1" ? -amount(line, from) : amount(line, from)
  def movements(file) = file.select { |l| l.start_with?("21") }

  VALID.each do |name|
    describe name do
      let(:lines) { read(name) }

      it "has records of exactly 128 characters, a header first and a trailer last" do
        expect(lines.map(&:length).uniq).to eq([ 128 ])
        expect(lines.first[0]).to eq("0")
        expect(lines.last[0]).to eq("9")
      end

      it "holds only records the specification knows, in an order it allows" do
        allowed = { "0" => %w[1], "1" => %w[2 3 8 9], "2" => %w[2 3 8], "3" => %w[2 3 8], "8" => %w[4 9], "4" => %w[4 9], "9" => %w[0] }
        expect(lines.map { |l| l[0] }.uniq - allowed.keys).to be_empty
        lines.each_cons(2) { |a, b| expect(allowed.fetch(a[0])).to include(b[0]), "#{a[0]} then #{b[0]}" }
      end

      it "counts its records and totals its movements in each trailer (the free messages are not counted)" do
        logical_files(lines).each do |file|
          trailer = file.last
          expect(trailer[16, 6].to_i).to eq(file.count { |l| l[0] =~ /[1238]/ })
          expect(amount(trailer, 22)).to eq(movements(file).select { |l| l[31] == "1" && l[6, 4] == "0000" }.sum(BigDecimal("0")) { |l| amount(l, 32) })
          expect(amount(trailer, 37)).to eq(movements(file).select { |l| l[31] == "0" && l[6, 4] == "0000" }.sum(BigDecimal("0")) { |l| amount(l, 32) })
        end
      end

      it "says in each trailer whether another file follows (1) or not (2)" do
        codes = logical_files(lines).map { |file| file.last[127] }

        expect(codes.last).to eq("2")
        expect(codes[0...-1].uniq - [ "1" ]).to be_empty
      end

      it "carries IBANs whose check digits are valid" do
        lines.grep(/\A1/).each do |old|
          iban = old[5, 34].strip
          next unless iban.start_with?("BE")

          digits = "#{iban[4..]}#{iban[0, 4]}".gsub(/[A-Z]/) { |c| (c.ord - 55).to_s }
          expect(digits.to_i % 97).to eq(1)
        end
      end

      it "numbers the detail of an information record after the movement it belongs to (spec §6)" do
        lines.each_cons(2) { |a, b| expect(b[2, 4]).to eq(a[2, 4]) if a.start_with?("2") && b.start_with?("3") }
      end
    end
  end

  (VALID - %w[integrity_mismatch empty_account]).each do |name|
    it "#{name}: old balance plus the movements equals the new balance, account by account" do
      logical_files(read(name)).each do |file|
        expect(signed(file[1], 42, 43) + movements(file).sum(BigDecimal("0")) { |l| signed(l, 31, 32) }).to eq(signed(file.find { |l| l.start_with?("8") }, 41, 42))
      end
    end
  end

  it "integrity_mismatch: does not add up, on purpose" do
    file = logical_files(read("integrity_mismatch")).first

    expect(signed(file[1], 42, 43) + movements(file).sum(BigDecimal("0")) { |l| signed(l, 31, 32) }).not_to eq(signed(file.find { |l| l.start_with?("8") }, 41, 42))
  end

  it "empty_account: is the records 0, 1 and 9 only, as an empty file is (spec §2)" do
    expect(read("empty_account").map { |l| l[0] }).to eq(%w[0 1 9])
  end

  it "two_accounts: is two logical files for two accounts" do
    files = logical_files(read("two_accounts"))

    expect(files.size).to eq(2)
    expect(files.map { |f| f[1][5, 34].strip }.uniq.size).to eq(2)
  end

  it "structured communications: type 101 with valid check digits in simple, wrong ones in invalid_structured" do
    digits = ->(name) { read(name).grep(/\A21/).filter_map { |l| l[65, 12] if l[61] == "1" && l[62, 3] == "101" } }

    expect(digits.("simple")).to all(satisfy { |d| Accounting::StructuredCommunication.valid?(d) })
    expect(digits.("simple")).not_to be_empty
    expect(digits.("invalid_structured")).to all(satisfy { |d| !Accounting::StructuredCommunication.valid?(d) })
  end

  it "transaction codes: type, family, operation, rubric (annex II): credit transfer in favour (01/50), simple transfer (01/01), costs (80/02)" do
    codes = read("simple").grep(/\A21/).map { |l| l[53, 8] }

    expect(codes).to include("00150000", "00101000", "08002000")
  end

  it "detailed_movement: carries 2.2, 2.3, two 3.1 and, after the new balance, two free messages (4)" do
    types = read("detailed_movement").map { |l| l[0] =~ /[23]/ ? l[0, 2] : l[0] }

    expect(types).to eq(%w[0 1 21 22 23 31 31 8 4 4 9])
  end

  it "detailed_movement: 2.2 holds the R-transaction type, reason, category purpose and purpose at the specified positions" do
    line = read("detailed_movement").find { |l| l.start_with?("22") }

    expect([ line[112], line[113, 4], line[117, 4], line[121, 4] ]).to eq([ "3", "MS03", "SUPP", "GDDS" ])
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
    expect(File.binread(FIXTURE_DIR.join("accents_latin1.cod"))).not_to eq(File.binread(FIXTURE_DIR.join("accents_cp850.cod")))
    expect(read("accents_latin1").join).to eq(read("accents_cp850").join)
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
