require "rails_helper"

# F02: the CODA parser (Febelfin standard v2.8, docs/dev/features/standard-coda-fr_-2025.pdf). Pure: bytes in, statements or
# errors out, nothing is written. A structural error rejects the whole file with the list of the faulty lines.
RSpec.describe Banking::Coda::Parser do
  CODA_FILES = Rails.root.join("spec/fixtures/files/coda")

  def parse(name) = described_class.call(File.binread(CODA_FILES.join("#{name}.cod")))
  def parse_text(text, **options) = described_class.call(text, **options)
  def statement(name) = parse(name).statements.sole
  def errors(result) = result.errors.map(&:message)

  describe "a simple statement" do
    subject(:statement) { parse("simple").statements.sole }

    it "succeeds with one statement" do
      expect(parse("simple")).to be_success
    end

    it "reads the account, its currency and its holder" do
      expect(statement).to have_attributes(iban: CodaBuilder.iban("539007547034"), currency: "EUR", holder: "ACME SRL", description: "COMPTE COURANT", sequence: 12)
    end

    it "reads the balances and their dates" do
      expect(statement).to have_attributes(old_balance: BigDecimal("1000.00"), old_balance_date: Date.new(2026, 3, 30),
                                           new_balance: BigDecimal("1842.50"), new_balance_date: Date.new(2026, 3, 31))
    end

    it "reads the movements with their signed amounts, dates and bank references" do
      lines = statement.lines

      expect(lines.map(&:amount)).to eq([ BigDecimal("1210.00"), BigDecimal("-605.00"), BigDecimal("-12.50"), BigDecimal("250.00") ])
      expect(lines.first).to have_attributes(value_date: Date.new(2026, 3, 2), entry_date: Date.new(2026, 3, 2), bank_reference: "BKREF0000000000000001", sequence: 1, detail: 0)
    end

    it "reads a valid structured communication (type 101) as its twelve digits" do
      expect(statement.lines.first).to have_attributes(structured_type: "101", structured_communication: Accounting::StructuredCommunication.for_id(1), structured_valid: true)
    end

    it "reads a free communication, and leaves a structured one out of it" do
      expect(statement.lines.second.communication).to eq("FACTURE F-2026-0042 BUREAU PLUS")
      expect(statement.lines.second.structured_communication).to be_nil
    end

    it "reads the counterparty: name, IBAN, BIC and the customer's own reference" do
      expect(statement.lines.first).to have_attributes(counterparty_name: "DUPONT ET FILS SPRL", counterparty_iban: CodaBuilder.iban("091012345678"),
                                                       counterparty_bic: "GKCCBEBB", customer_reference: "VIREMENT FACTURE 1")
    end

    it "breaks the transaction code into type, family, operation and rubric (spec §3)" do
      expect(statement.lines.first.transaction).to eq(type: "0", family: "01", operation: "50", rubric: "000")
      expect(statement.lines.third.transaction).to include(family: "80", operation: "02")
    end

    it "checks that the old balance plus the movements gives the new balance" do
      expect(statement).to be_integrity_ok
    end

    it "keeps the records of each movement, as they came" do
      expect(statement.lines.first.raw.map { |r| r[0, 2] }).to eq(%w[21 22 23])
      expect(statement.lines.first.raw).to all(satisfy { |record| record.length == 128 })
    end
  end

  describe "several accounts in one file" do
    it "gives one statement per logical file" do
      statements = parse("two_accounts").statements

      expect(statements.map(&:iban)).to eq([ CodaBuilder.iban("539007547034"), CodaBuilder.iban("310123456789") ])
      expect(statements.last.lines.sole.counterparty_iban).to eq(CodaBuilder.iban("539007547034"))
    end
  end

  describe "an account without movement" do
    it "is a statement with no line and no new balance" do
      statement = statement("empty_account")

      expect(statement.lines).to be_empty
      expect(statement.new_balance).to be_nil
      expect(statement.old_balance).to eq(BigDecimal("1234.56"))
      expect(statement).to be_empty
    end
  end

  describe "the sub-records" do
    subject(:line) { statement("detailed_movement").lines.sole }

    it "reads the information records (3.1) into the movement" do
      expect(line.information).to eq([ "DETAIL 1 ORDRE PERMANENT", "DETAIL 2 SUITE" ])
    end

    it "reads the R-transaction type, the reason and the purposes of the 2.2" do
      expect(line).to have_attributes(r_type: "3", iso_reason: "MS03", category_purpose: "SUPP", purpose: "GDDS", customer_reference: "CLIENT-REF-77")
    end

    it "reads the free messages (4), which belong to the statement" do
      expect(statement("detailed_movement").messages).to eq([ "MESSAGE LIBRE DE LA BANQUE", "SECOND MESSAGE" ])
    end
  end

  describe "encodings" do
    it "converts ISO-8859-1 and CP850 to UTF-8, whichever the bank used" do
      latin = statement("accents_latin1")
      cp850 = statement("accents_cp850")

      expect(latin.holder).to eq("ACME SRL")
      expect(latin.lines.sole.counterparty_name).to eq("JOSE GARCIA-LOPEZ")
      expect(latin.lines.sole.communication).to eq("REMBOURSEMENT FRAIS DEPLACEMENT ÉCOLE DES BEAUX-ARTS ÇA ÜBER")
      expect(cp850.lines.sole.communication).to eq(latin.lines.sole.communication)
    end

    it "reads the name of the addressee in the header, accents included" do
      expect(statement("accents_cp850").addressee).to eq("SOCIÉTÉ ACME")
      expect(statement("accents_latin1").addressee).to eq("SOCIÉTÉ ACME")
    end

    it "accepts text that is already UTF-8" do
      text = File.binread(CODA_FILES.join("accents_latin1.cod")).force_encoding("ISO-8859-1").encode("UTF-8")

      expect(parse_text(text).statements.sole.addressee).to eq("SOCIÉTÉ ACME")
    end

    it "lets the caller say which encoding to use" do
      expect(described_class.call(File.binread(CODA_FILES.join("accents_cp850.cod")), encoding: "CP850").statements.sole.addressee).to eq("SOCIÉTÉ ACME")
    end
  end

  describe "what is flagged but not refused" do
    it "marks a structured communication whose check digits are wrong" do
      line = statement("invalid_structured").lines.sole

      expect(line.structured_valid).to be false
      expect(line.structured_communication).to be_present
    end

    it "marks a statement that does not add up as to be reviewed" do
      statement = statement("integrity_mismatch")

      expect(statement).not_to be_integrity_ok
      expect(statement.integrity_gap).to eq(BigDecimal("5555.55") - BigDecimal("1842.50"))
    end

    it "reads a foreign currency account" do
      expect(statement("usd_account")).to have_attributes(currency: "USD", new_balance: BigDecimal("1699.50"))
    end
  end

  describe "a file that is refused whole" do
    {
      "broken_length"  => /line 4.*130 characters instead of 128/i,
      "truncated"      => /no trailer|record 9/i,
      "unknown_record" => /line 3.*unknown record type "7"/i,
      "not_coda"       => /line 1/i
    }.each do |name, message|
      it "#{name}: gives the faulty lines and no statement" do
        result = parse(name)

        expect(result).not_to be_success
        expect(result.statements).to be_empty
        expect(errors(result).join(" | ")).to match(message)
        expect(result.errors).to all(respond_to(:line))
      end
    end

    it "lists every faulty line, not only the first" do
      lines = CodaBuilder.file(statements: [ { movements: [ { amount: "10.00" }, { amount: "20.00" } ] } ]).split("\r\n")
      lines[2] = lines[2][0, 100]
      lines[3] = lines[3][0, 90]

      expect(errors(parse_text(lines.join("\r\n"))).grep(/characters instead of 128/).size).to eq(2)
    end

    it "refuses an empty file" do
      expect(parse_text("")).not_to be_success
    end
  end

  describe "structure checks" do
    def broken(index = nil, &change)
      lines = CodaBuilder.file(statements: [ { movements: [ { amount: "10.00", free: "X" } ] } ]).split("\r\n")
      change.call(lines)
      parse_text(lines.join("\r\n"))
    end

    it "refuses a record that is out of place (a movement before the old balance)" do
      result = broken { |l| l[1], l[2] = l[2], l[1] }

      expect(result).not_to be_success
      expect(errors(result).join).to match(/line 3|line 2/)
    end

    it "refuses a free message (4) before the new balance" do
      result = broken { |l| l.insert(2, CodaBuilder.free_message("TOO EARLY", 1, last: true)) }

      expect(errors(result).join).to match(/record 4/i)
    end

    it "refuses an amount that is not a number" do
      result = broken { |l| l[2] = l[2].dup.tap { |r| r[32, 15] = "00000000ABC0000" } }

      expect(errors(result).join).to match(/line 3.*amount/i)
    end

    it "refuses a date that does not exist" do
      result = broken { |l| l[2] = l[2].dup.tap { |r| r[47, 6] = "310226" } }

      expect(errors(result).join).to match(/line 3.*date/i)
    end

    it "accepts 000000 as an unknown value date" do
      lines = CodaBuilder.file(statements: [ { movements: [ { amount: "10.00" } ] } ]).split("\r\n")
      lines[2] = lines[2].dup.tap { |r| r[47, 6] = "000000" }

      expect(parse_text(lines.join("\r\n")).statements.sole.lines.sole.value_date).to be_nil
    end

    it "refuses a trailer that counts the wrong number of records" do
      result = broken { |l| l[-1] = l[-1].dup.tap { |r| r[16, 6] = "000099" } }

      expect(errors(result).join).to match(/trailer.*99.*3/i)
    end

    it "refuses a file whose first record is not a header" do
      result = broken { |l| l.shift }

      expect(errors(result).join).to match(/line 1/)
    end

    it "refuses an account structure it does not know" do
      result = broken { |l| l[1] = l[1].dup.tap { |r| r[1] = "9" } }

      expect(errors(result).join).to match(/line 2.*account structure/i)
    end

    it "refuses a sign that is neither credit nor debit" do
      result = broken { |l| l[2] = l[2].dup.tap { |r| r[31] = "5" } }

      expect(errors(result).join).to match(/line 3.*sign/i)
    end
  end

  describe "tolerances" do
    let(:text) { CodaBuilder.file(statements: [ { movements: [ { amount: "10.00", free: "X" } ] } ]) }

    it "accepts LF line ends and a missing final line end" do
      expect(parse_text(text.gsub("\r\n", "\n").chomp)).to be_success
    end

    it "accepts a final end-of-file character (0x1A)" do
      expect(parse_text("#{text}\x1A")).to be_success
    end

    it "accepts a file without line ends, cut every 128 characters" do
      expect(parse_text(text.delete("\r\n"))).to be_success
    end

    it "ignores blank lines at the end" do
      expect(parse_text("#{text}\r\n\r\n")).to be_success
    end
  end

  describe "the account number (spec §7.5)" do
    def with_structure(structure, field)
      lines = CodaBuilder.file(statements: [ { movements: [ { amount: "10.00" } ] } ]).split("\r\n")
      lines[1] = lines[1].dup.tap { |r| r[1] = structure; r[5, 37] = field.ljust(37) }
      lines[3] = lines[3].dup.tap { |r| r[4, 37] = field.ljust(37) }
      parse_text(lines.join("\r\n"))
    end

    it "derives the IBAN of a Belgian BBAN (structure 0), currency after the blank" do
      result = with_structure("0", "539007547034 EUR")

      expect(result.statements.sole).to have_attributes(iban: CodaBuilder.iban("539007547034"), currency: "EUR")
    end

    it "reads a foreign BBAN (structure 1) as it is" do
      expect(with_structure("1", "GB29NWBK60161331926819".ljust(34) + "GBP").statements.sole).to have_attributes(iban: nil, account_number: "GB29NWBK60161331926819", currency: "GBP")
    end

    it "reads a foreign IBAN (structure 3)" do
      expect(with_structure("3", "NL91ABNA0417164300".ljust(34) + "EUR").statements.sole).to have_attributes(iban: "NL91ABNA0417164300", currency: "EUR")
    end
  end

  describe "the header" do
    it "gives the creation date, the bank, the BIC and whether the file is a duplicate" do
      result = statement("simple")

      expect(result.header).to include(created_on: Date.new(2026, 3, 31), bank_id: "539", bic: "GEBABEBB", duplicate: false, file_reference: "0000000001")
    end

    it "marks a duplicate (D in position 17)" do
      lines = CodaBuilder.file(statements: [ { movements: [] } ]).split("\r\n")
      lines[0] = lines[0].dup.tap { |r| r[16] = "D" }

      expect(parse_text(lines.join("\r\n")).statements.sole.header[:duplicate]).to be true
    end
  end

  describe "the fingerprint of a line" do
    it "is the same for the same movement in two files, and different for another" do
      first  = parse("overlap_a").statements.sole.lines
      second = parse("overlap_b").statements.sole.lines

      expect(first.map(&:fingerprint)).to eq(second.first(2).map(&:fingerprint))
      expect(second.map(&:fingerprint).uniq.size).to eq(3)
    end

    it "does not depend on the sequence of the movement in its file" do
      a = parse_text(CodaBuilder.file(statements: [ { movements: [ { amount: "10.00", bank_reference: "R1", free: "A" }, { amount: "20.00", bank_reference: "R2", free: "B" } ] } ])).statements.sole.lines
      b = parse_text(CodaBuilder.file(statements: [ { movements: [ { amount: "20.00", bank_reference: "R2", free: "B" } ] } ])).statements.sole.lines

      expect(b.first.fingerprint).to eq(a.last.fingerprint)
    end
  end

  describe "globalisation (spec §6, §7.2.2)" do
    it "keeps the detail movements of a bank total behind the total, which alone counts for the balance" do
      lines = CodaBuilder.file(statements: [ { new_balance: "10.00", movements: [ { amount: "10.00", free: "TOTAL" }, { amount: "10.00", free: "DETAIL", bank_reference: "D1" } ] } ]).split("\r\n")
      lines[3] = lines[3].dup.tap { |r| r[2, 4] = "0001"; r[6, 4] = "0001" } # the second 2.1: same sequence, detail 1
      statement = parse_text(lines.join("\r\n")).statements.sole

      expect(statement.lines.size).to eq(1)
      expect(statement.lines.first.details.sole).to have_attributes(communication: "DETAIL", detail: 1)
      expect(statement).to be_integrity_ok
    end
  end

  describe "structured communication of type 100 (ISO 11649 creditor reference)" do
    it "is read as the reference and checked" do
      reference = "RF#{format('%02d', 98 - "5390075470340271500".to_i % 97)}5390075470340"
      line = parse_text(CodaBuilder.file(statements: [ { movements: [ { amount: "10.00", structured_type: "100", structured: reference } ] } ])).statements.sole.lines.sole

      expect(line).to have_attributes(structured_type: "100", structured_communication: reference, structured_valid: true)
    end
  end

  describe "the interface" do
    it "is a Banking::StatementParser, so that CAMT.053 can come later without touching the rest" do
      expect(described_class.ancestors).to include(Banking::StatementParser)
      expect(Banking::StatementParser.instance_method(:call)).to be_present
    end
  end
end
