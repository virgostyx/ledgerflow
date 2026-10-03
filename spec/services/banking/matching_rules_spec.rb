require "rails_helper"

# F02 §"Rapprochement automatique": the rules, in order, the first that produces a result wins, with a confidence score.
# 1 structured communication (100), 2 invoice number (95), 3 amount + IBAN (90), 4 amount + similar name (75), 5 grouped payment (80).
RSpec.describe Accounting::MatchBankTransaction, "rules and scores" do
  include_context "with_open_fiscal_year"

  let(:bank_account) { create(:bank_account) }
  let(:partner) { create(:partner, name: "DUPONT ET FILS SPRL", iban: CodaBuilder.iban("091012345678")) }

  def invoice(total, partner: self.partner, number: nil, **attrs)
    create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner, **attrs).tap do |i|
      i.update_columns(total_incl_vat: BigDecimal(total.to_s), invoice_number: number || i.invoice_number)
    end
  end

  def line(amount, **attrs) = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s), **attrs)
  def suggest(tx) = described_class.call(transaction: tx)

  describe "rule 1: structured communication and identical amount" do
    it "scores 100, high" do
      target = invoice(1210)
      tx = line(1210, description: Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(target.id)))

      expect(suggest(tx)).to have_attributes(kind: :invoice, target: target, score: 100, rule: 1, confidence: :high)
    end

    it "scores less when the amount differs (partial payment or overpayment)" do
      target = invoice(1210)
      tx = line(500, description: Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(target.id)))

      expect(suggest(tx)).to have_attributes(kind: :invoice, rule: 1, score: 80, confidence: :medium)
    end
  end

  describe "rule 2: the invoice number in the communication, identical amount" do
    it "scores 95" do
      target = invoice(605, number: "VT2026/0042")

      expect(suggest(line(605, description: "PAIEMENT VT2026/0042 MERCI"))).to have_attributes(kind: :invoice, target: target, score: 95, rule: 2, confidence: :high)
    end

    it "does not match when the amount differs, nor on a number that is only part of a longer one" do
      invoice(605, number: "VT2026/0042")

      expect(suggest(line(600, description: "VT2026/0042"))).to be_nil
      expect(suggest(line(605, description: "VT2026/00421"))).to be_nil
    end
  end

  describe "rule 3: identical amount, the counterparty's IBAN is the partner's, a single candidate" do
    it "scores 90" do
      target = invoice(300)

      expect(suggest(line(300, counterparty_iban: partner.iban, description: "x"))).to have_attributes(kind: :invoice, target: target, score: 90, rule: 3, confidence: :high)
    end

    it "reads the IBAN whatever its spacing or case" do
      invoice(300)
      partner.update!(iban: partner.iban.scan(/.{1,4}/).join(" ").downcase)

      expect(suggest(line(300, counterparty_iban: CodaBuilder.iban("091012345678")))).to have_attributes(rule: 3)
    end

    it "gives nothing when two invoices of that partner have the same amount" do
      invoice(300)
      invoice(300)

      expect(suggest(line(300, counterparty_iban: partner.iban))).to be_nil
    end

    it "gives nothing for another partner's IBAN or another amount" do
      invoice(300)

      expect(suggest(line(300, counterparty_iban: CodaBuilder.iban("999999999999")))).to be_nil
      expect(suggest(line(301, counterparty_iban: partner.iban))).to be_nil
    end
  end

  describe "rule 4: identical amount, a counterparty name close to the partner's (similarity 0.6 at least), a single candidate" do
    it "scores 75" do
      target = invoice(450)

      expect(suggest(line(450, counterparty_name: "DUPONT & FILS SPRL"))).to have_attributes(kind: :invoice, target: target, score: 75, rule: 4, confidence: :medium)
    end

    it "ignores accents and case" do
      target = invoice(450, partner: create(:partner, name: "Société Générale Électrique"))

      expect(suggest(line(450, counterparty_name: "SOCIETE GENERALE ELECTRIQUE"))).to have_attributes(target: target, rule: 4)
    end

    it "gives nothing for a name that is not close enough" do
      invoice(450)

      expect(suggest(line(450, counterparty_name: "MARTIN JEAN"))).to be_nil
    end

    it "gives nothing when two partners are as close and both have an invoice of that amount" do
      invoice(450)
      invoice(450, partner: create(:partner, name: "DUPONT ET FILS SA"))

      expect(suggest(line(450, counterparty_name: "DUPONT ET FILS"))).to be_nil
    end
  end

  describe "rule 5: a grouped payment, the open invoices of one partner adding up to the amount" do
    it "scores 80 when exactly one combination gives the amount" do
      a = invoice(100)
      b = invoice(250)
      invoice(1000)

      expect(suggest(line(350, counterparty_iban: partner.iban))).to have_attributes(kind: :invoices, score: 80, rule: 5, confidence: :medium, target: contain_exactly(a, b))
    end

    it "finds the partner by name as well" do
      a = invoice(100)
      b = invoice(250)

      expect(suggest(line(350, counterparty_name: "DUPONT ET FILS"))).to have_attributes(kind: :invoices, target: contain_exactly(a, b), rule: 5)
    end

    it "gives nothing when two combinations give the amount" do
      invoice(100)
      invoice(250)
      invoice(150)
      invoice(200)

      expect(suggest(line(350, counterparty_iban: partner.iban))).to be_nil
    end

    it "only looks at ten open invoices, the oldest first" do
      # the first ten are powers of two (every sum is unique), the last two are far bigger
      invoices = (Array.new(10) { |i| 2**i } + [ 2000, 3000 ]).each_with_index.map { |amount, i| invoice(amount, due_date: Date.current + i) }

      expect(suggest(line(3, counterparty_iban: partner.iban)).target).to contain_exactly(invoices[0], invoices[1])
      expect(suggest(line(5000, counterparty_iban: partner.iban))).to be_nil # only the 11th and 12th would give it
    end
  end

  describe "the order of the rules" do
    it "keeps the first rule that gives a result" do
      by_number = invoice(300, number: "VT2026/0007")
      invoice(300, partner: create(:partner, name: "OTHER", iban: CodaBuilder.iban("001234567890")))

      expect(suggest(line(300, description: "VT2026/0007", counterparty_iban: partner.iban))).to have_attributes(target: by_number, rule: 2)
    end
  end

  describe "a payment to a supplier (a debit)" do
    let(:supplier) { create(:partner, :supplier, name: "BUREAU PLUS SA", iban: CodaBuilder.iban("737000012345")) }

    def supplier_invoice(total, **attrs)
      create(:invoice, :supplier, :posted, fiscal_year: fiscal_year, partner: supplier, **attrs).tap { |i| i.update_columns(total_incl_vat: BigDecimal(total.to_s)) }
    end

    it "is matched by the supplier's reference in the communication (rule 2)" do
      target = supplier_invoice(605, supplier_reference: "F-2026-0042")

      expect(suggest(line(-605, description: "FACTURE F-2026-0042 BUREAU PLUS"))).to have_attributes(kind: :supplier_invoice, target: target, score: 95, rule: 2)
    end

    it "is matched by the supplier's IBAN and the amount (rule 3)" do
      target = supplier_invoice(605)

      expect(suggest(line(-605, counterparty_iban: supplier.iban))).to have_attributes(kind: :supplier_invoice, target: target, score: 90, rule: 3)
    end

    it "is never mixed up with customer invoices" do
      invoice(605)

      expect(suggest(line(-605, counterparty_iban: partner.iban))).to be_nil
    end
  end

  describe "rule 6: a bank rule of the entity" do
    let(:fees_account) { create(:account, code: "651100", label_fr: "Frais bancaires") }

    def rule(**attrs) = Accounting::BankRule.create!({ name: "Bank fees", condition_type: "contains", condition_value: "frais de tenue", account: fees_account }.merge(attrs))

    it "proposes the rule with its own score" do
      rule(score: 85)

      expect(suggest(line(-12.5, description: "FRAIS DE TENUE DE COMPTE"))).to have_attributes(kind: :rule, score: 85, rule: 6, confidence: :medium, target: Accounting::BankRule.first)
    end

    it "comes after the rules on invoices" do
      rule(condition_type: "contains", condition_value: "dupont")
      target = invoice(300)

      expect(suggest(line(300, counterparty_name: "DUPONT ET FILS SPRL", counterparty_iban: partner.iban))).to have_attributes(kind: :invoice, target: target, rule: 3)
    end

    it "takes the first rule by priority" do
      rule(name: "second", priority: 20, condition_value: "tenue de compte", account: create(:account, code: "613000"))
      first = rule(name: "first", priority: 10)

      expect(suggest(line(-12.5, description: "frais de tenue")).target).to eq(first)
    end

    it "ignores a rule that is switched off" do
      rule(active: false)

      expect(suggest(line(-12.5, description: "FRAIS DE TENUE"))).to be_nil
    end

    it "is per entity" do
      ActsAsTenant.with_tenant(create(:entity)) { Accounting::BankRule.create!(name: "x", condition_type: "contains", condition_value: "tenue", account: create(:account, code: "651100")) }

      expect(suggest(line(-12.5, description: "FRAIS DE TENUE"))).to be_nil
    end
  end

  describe "what the engine leaves alone" do
    it "does not look at a line that is not pending" do
      invoice(300)

      expect(suggest(line(300, counterparty_iban: partner.iban, status: :ignored))).to be_nil
    end

    it "does not match an amount in a foreign currency" do
      invoice(300)
      usd = create(:bank_account, currency: "USD")

      expect(suggest(create(:bank_transaction, bank_account: usd, amount: 300, currency: "USD", counterparty_iban: partner.iban))).to be_nil
    end
  end
end
