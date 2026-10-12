require "rails_helper"

# B01b §5 "Composition du lot": a batch is made of eligible invoices, grouped by supplier, with part payments and credit notes netted. All or nothing.
RSpec.describe Payments::ComposeBatch do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:today) { Date.current }
  let(:execution) { today + 2 }
  let(:bank) { create(:bank_account, currency: "EUR") }
  let(:preparer) { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:supplier) { create(:partner, :supplier, name: "Acme Ltd", iban: nil) }
  let!(:acme_account) { create(:partner_bank_account, :verified, partner: supplier, iban: "BE68539007547034", created_by: owner) }
  let(:other_supplier) { create(:partner, :supplier, name: "Beta SA", iban: nil) }
  let!(:beta_account) { create(:partner_bank_account, :verified, partner: other_supplier, iban: "FR1420041010050500013M02606", created_by: owner) }

  def posted(partner: supplier, unit_price: 1000, payment_reference: nil, document_type: :invoice, due: today + 3)
    invoice = create(:invoice, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, partner: partner, due_date: due, document_type: document_type, payment_reference: payment_reference)
    create(:invoice_line, invoice: invoice, account: account_604, unit_price: unit_price, quantity: 1, vat_rate: "21.00")
    result = Accounting::PostInvoice.call(invoice: invoice)
    raise result.message if result.failure?

    invoice.reload
  end

  def compose(*selections, user: preparer, **options)
    described_class.call(bank_account: bank, execution_date: execution, selections: selections.map { |s| s.is_a?(Hash) ? s : { invoice_id: s.id } }, user: user, **options)
  end

  def audit(action) = Accounting::AuditLog.where(auditable_type: "Payments::Batch", action: action)

  describe "a batch of invoices" do
    it "is a draft with a reference of its own, one payment per supplier, the account of each as it was, and the totals" do
      a = posted(unit_price: 1000)
      b = posted(unit_price: 500, partner: other_supplier)

      result = compose(a, b)
      batch = result[:batch]

      expect(result).to be_success
      expect(batch).to be_draft
      expect(batch.reference).to eq("PAY-#{today.year}-0001")
      expect(batch).to have_attributes(bank_account: bank, requested_execution_date: execution, prepared_by: preparer, total: BigDecimal("1815.00"), payments_count: 2)
      expect(batch.items.map { |i| [ i.partner.name, i.amount, i.iban, i.partner_bank_account ] }).to contain_exactly(
        [ "Acme Ltd", BigDecimal("1210.00"), "BE68539007547034", acme_account ], [ "Beta SA", BigDecimal("605.00"), "FR1420041010050500013M02606", beta_account ]
      )
      expect(batch.items.flat_map(&:item_invoices).map(&:invoice)).to contain_exactly(a, b)
      log = audit("payment_batch_composed").sole
      expect(log).to have_attributes(user_id: preparer.id)
      expect(log.payload).to include("reference" => batch.reference, "total" => "1815.00", "payments" => 2)
      expect(Accounting::AuditLog.pluck(:payload).to_json).not_to include("BE68539007547034")
    end

    it "numbers the batches one after the other within the year" do
      compose(posted)
      second = compose(posted)

      expect(second[:batch].reference).to eq("PAY-#{today.year}-0002")
    end

    it "groups the invoices of a supplier in one payment, with a free remittance that lists their numbers" do
      a = posted
      b = posted(unit_price: 200)

      item = compose(a, b)[:batch].items.sole

      expect(item.amount).to eq(BigDecimal("1452.00"))
      expect(item.item_invoices.count).to eq(2)
      expect(item).not_to be_structured_remittance
      expect(item.remittance).to eq("Invoices #{[ a, b ].map(&:invoice_number).join(', ')}")
    end

    it "keeps within 140 characters of remittance, and gives the end-to-end identifier of at most 35 safe characters, the same for the same batch" do
      many = Array.new(12) { posted(unit_price: 10) }
      batch = compose(*many)[:batch]

      expect(batch.items.sole.remittance.length).to be <= 140
      expect(batch.items.map(&:end_to_end_id)).to all(match(/\A[A-Za-z0-9-]{1,35}\z/))
      expect(batch.items.first.end_to_end_id).to eq("#{batch.reference}-1")
    end

    it "pays an invoice that carries a structured communication on its own, with that communication" do
      structured = posted(payment_reference: "+++090/9337/55493+++")
      plain = posted

      items = compose(structured, plain)[:batch].items.order(:id)

      expect(items.size).to eq(2)
      paid = items.find(&:structured_remittance)
      expect(paid.remittance).to eq("090933755493")
      expect(paid.item_invoices.sole.invoice).to eq(structured)
    end
  end

  describe "part payments" do
    it "pays the amount asked for, and leaves the rest open" do
      invoice = posted

      batch = compose({ invoice_id: invoice.id, amount: "400.00" })[:batch]

      expect(batch.items.sole.amount).to eq(BigDecimal("400.00"))
      expect(batch.items.sole.item_invoices.sole.amount).to eq(BigDecimal("400.00"))
      expect(batch.total).to eq(BigDecimal("400.00"))
    end

    it "refuses more than the rest, nothing, and a negative amount" do
      invoice = posted

      [ "1210.01", "0", "-5", "lots" ].each do |amount|
        result = compose({ invoice_id: invoice.id, amount: amount })

        expect(result).to be_failure, amount
        expect(result.message).to match(/amount/i)
      end
      expect(Payments::Batch.count).to eq(0)
    end
  end

  describe "what is refused" do
    it "an invoice that is not eligible, with its reason, and the whole batch is not made" do
      good = posted
      bad = posted(partner: create(:partner, :supplier, name: "No Account SA", iban: nil))

      result = compose(good, bad)

      expect(result).to be_failure
      expect(result.message).to include("No Account SA").and include("No bank account")
      expect(Payments::Batch.count).to eq(0)
    end

    it "an empty selection, and the same invoice twice" do
      invoice = posted

      expect(compose).to be_failure
      twice = compose(invoice, invoice)
      expect(twice).to be_failure
      expect(twice.message).to match(/picked twice/) # said clearly, not left to the database to refuse
    end

    it "an invoice that another active batch took in the meantime, even if two people composed at once" do
      invoice = posted
      compose(invoice)

      result = compose(invoice)

      expect(result).to be_failure
      expect(result.message).to include("PAY-#{today.year}-0001")
      expect(Payments::Batch.count).to eq(1)
    end

    it "when the database refuses (another batch took the invoice after the check), nothing is left half-made" do
      invoice = posted
      allow(Payments::Eligibility).to receive(:call).and_wrap_original do |original, **args|
        original.call(**args).tap do # the check saw it free ... and then another batch took it
          other = Payments::Batch.create!(bank_account: bank, reference: "LOT-X", requested_execution_date: execution)
          taken = other.items.create!(partner: supplier, iban: acme_account.iban, holder_name: "Acme Ltd", amount: "1.00", end_to_end_id: "X1", remittance: "x")
          taken.item_invoices.create!(invoice: invoice, amount: "1.00")
        end
      end

      result = compose(invoice)

      expect(result).to be_failure
      expect(result.message).to match(/another batch/i)
      expect(Payments::Batch.where.not(reference: "LOT-X")).to be_empty
    end

    it "a bank account that is not in euros" do
      usd = create(:bank_account, currency: "USD")

      result = described_class.call(bank_account: usd, execution_date: execution, selections: [ { invoice_id: posted.id } ], user: preparer)

      expect(result).to be_failure
      expect(result.message).to match(/EUR/)
    end

    it "someone who may not prepare a batch, and an entity that has the feature off" do
      reader = create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) }
      invoice = posted
      expect(compose(invoice, user: reader)).to be_failure

      entity.update!(features: entity.features.merge("b01b" => false))
      expect(compose(invoice)).to be_failure
    end
  end

  describe "credit notes" do
    it "are netted against the invoices of the supplier when asked: the payment is the net, and the note is used up" do
      invoice = posted(unit_price: 1000)
      note = posted(unit_price: 200, document_type: :credit_note) # 242.00

      result = compose(invoice, net_credit_notes: true)
      item = result[:batch].items.sole

      expect(item.amount).to eq(BigDecimal("968.00"))
      expect(item.item_invoices.map { |l| [ l.invoice, l.amount ] }).to contain_exactly([ invoice, BigDecimal("1210.00") ], [ note, BigDecimal("-242.00") ])
      expect(Payments::ItemInvoice.where(invoice: note, active: true)).to exist
    end

    it "are left alone when not asked" do
      invoice = posted
      posted(unit_price: 200, document_type: :credit_note)

      item = compose(invoice)[:batch].items.sole

      expect(item.amount).to eq(BigDecimal("1210.00"))
    end

    it "make no payment at all when they cover the invoices, and the supplier is listed to be netted by hand" do
      invoice = posted(unit_price: 100) # 121.00
      posted(unit_price: 1000, document_type: :credit_note)
      other = posted(partner: other_supplier, unit_price: 100)

      result = compose(invoice, other, net_credit_notes: true)

      expect(result).to be_success
      expect(result[:batch].items.map { |i| i.partner.name }).to eq([ "Beta SA" ])
      expect(result[:to_net].map { |s| s.name }).to eq([ "Acme Ltd" ])
    end

    it "do not make a batch of nothing: only netted suppliers is a refusal" do
      invoice = posted(unit_price: 100)
      posted(unit_price: 1000, document_type: :credit_note)

      result = compose(invoice, net_credit_notes: true)

      expect(result).to be_failure
      expect(Payments::Batch.count).to eq(0)
    end

    it "use only what the invoices of the batch can take: a credit note bigger than the invoices is not consumed" do
      invoice = posted(unit_price: 100)
      note = posted(unit_price: 1000, document_type: :credit_note)
      other = posted(unit_price: 300, partner: other_supplier)

      compose(invoice, other, net_credit_notes: true)

      expect(Payments::ItemInvoice.where(invoice: note)).to be_empty
    end
  end
end
