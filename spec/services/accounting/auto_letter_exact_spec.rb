require "rails_helper"

# F04 §7 criterion 7: auto_reconcile_exact letters only suggestions of score 100, marks them automatic, and leaves a trace in the audit.
RSpec.describe Accounting::AutoLetterExact do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:supplier) { create(:partner, :supplier) }
  let(:od)       { create(:journal, :cash) }

  def line(debit: 0, credit: 0, reference: nil, communication: nil, date: fiscal_year.start_date + 20)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: date, **(reference ? { reference: reference } : {}))
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:bank_transaction, journal_entry: entry, structured_communication: communication) if communication
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  let!(:invoice) { line(credit: 121, reference: "FAC-2026-0042") }
  let!(:payment) { line(debit: 121, communication: "FAC-2026-0042") }
  let!(:near_a)  { line(credit: 80) }
  let!(:near_b)  { line(debit: 80) } # rule 3 (90): never applied alone

  before { Accounting::SuggestLetterings.call }

  it "does nothing while the option is off" do
    expect(described_class.call).to eq(0)
    expect(invoice.reload.lettering_id).to be_nil
  end

  context "when the option is on" do
    before { entity.update!(auto_reconcile_exact: true) }

    it "letters the score-100 suggestion only, as automatic" do
      expect(described_class.call).to eq(1)

      expect(invoice.reload.lettering_id).to eq(payment.reload.lettering_id)
      expect(Accounting::Lettering.find(invoice.lettering_id).auto).to be(true)
      expect(near_a.reload.lettering_id).to be_nil
      expect(Accounting::LetteringSuggestion.accepted.sole.score).to eq(100)
    end

    it "leaves a trace in the audit trail" do
      described_class.call

      log = Accounting::AuditLog.where(action: "auto_lettering").sole
      expect(log.user_id).to be_nil
      expect(log.payload).to include("rule" => 1, "line_ids" => [ invoice.id, payment.id ].sort)
    end

    it "can be undone like any other lettering" do
      described_class.call

      expect(Accounting::UnletterLines.call(lettering: invoice.reload.lettering, reason: "wrong match")).to be_success
      expect(invoice.reload.lettering_id).to be_nil
    end
  end
end

RSpec.describe Accounting::SuggestLetteringsJob, "with the option" do
  include_context "with_open_fiscal_year"

  it "applies the exact suggestions after refreshing them" do
    entity.update!(auto_reconcile_exact: true)
    order = []
    allow(Accounting::SuggestLetterings).to receive(:call) { order << [ :suggest, ActsAsTenant.current_tenant.id ] }
    allow(Accounting::AutoLetterExact).to receive(:call) { order << [ :auto, ActsAsTenant.current_tenant.id ] }

    described_class.perform_now

    expect(order.index([ :suggest, entity.id ])).to be < order.index([ :auto, entity.id ])
  end
end
