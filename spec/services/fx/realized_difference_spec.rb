require "rails_helper"

# F11, realized exchange differences: lettering is done in the currency; the difference in EUR is an entry the lettering generates, posted by itself,
# dated at the latest line, linked to the lettering and undone with it.
RSpec.describe "Lettering in a foreign currency" do
  include_context "with_open_fiscal_year"

  let(:sales)    { create(:journal, :sale) }
  let(:bank_journal) { create(:journal, :purchase, code: "BNK", label_fr: "Bank") }
  let!(:misc)      { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let!(:customers) { create(:account, :customer, code: "400000", reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit) }
  let!(:bank)      { create(:account, code: "550000", account_type: :asset, normal_balance: :debit) }
  let!(:fx_loss)   { create(:account, code: "651200", account_type: :expense, normal_balance: :debit) }
  let!(:fx_gain)   { create(:account, code: "751100", account_type: :revenue, normal_balance: :credit) }
  let(:partner)    { create(:partner, name: "Acme Ltd", payment_terms_days: 0) }
  let(:user)       { create(:user) }

  # Posts an entry from lines [account, side, eur, foreign, currency, rate], and returns the posted lines by account.
  def post_entry(date, journal, *lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each do |account, side, eur, foreign, currency, rate|
      attrs = { journal_entry: entry, account: account, partner: (partner if account == customers), side => BigDecimal(eur.to_s), (side == :debit ? :credit : :debit) => BigDecimal("0") }
      attrs.merge!(currency: currency, amount_currency: (side == :debit ? 1 : -1) * BigDecimal(foreign.to_s), exchange_rate: BigDecimal(rate.to_s)) if foreign
      create(:journal_entry_line, **attrs)
    end
    result = Accounting::PostJournalEntry.call(entry: entry)
    raise result.message if result.failure?

    entry.reload.lines.index_by(&:account)
  end

  let(:invoice_day) { Date.current - 20 }
  let(:payment_day) { Date.current - 5 }
  let!(:invoice_line) { post_entry(invoice_day, sales, [ customers, :debit, "909.09", "1000", "USD", "1.10" ], [ revenue, :credit, "909.09", "1000", "USD", "1.10" ])[customers] }

  def pay(eur:, foreign: "1000", currency: "USD", rate: nil, date: payment_day)
    rate ||= (BigDecimal(foreign) / BigDecimal(eur)).round(8)
    post_entry(date, bank_journal, [ bank, :debit, eur, nil ], [ customers, :credit, eur, foreign, currency, rate ])[customers]
  end

  def letter(*lines, **opts) = Accounting::LetterLines.call(lines: lines, user: user, **opts)
  def fx_entry = Accounting::JournalEntry.find_by(source_type: Accounting::JournalEntry::FX_SOURCE)

  describe "a payment at a rate other than the invoice's (criterion 2)" do
    it "balances in USD, and books the exact difference in EUR on the loss account when less came in than was booked" do
      payment = pay(eur: "800.00") # 1 000 USD at 1.25
      result = letter(invoice_line, payment)

      expect(result).to be_success, result.message
      lettering = result[:lettering]
      expect([ invoice_line, payment ].sum { |l| l.reload.amount_currency }).to eq(0)
      expect(fx_entry.lines.find_by(account: fx_loss)).to have_attributes(debit: BigDecimal("109.09"))
      expect(fx_entry.lines.find_by(account: customers)).to have_attributes(credit: BigDecimal("109.09"), lettering_id: lettering.id)
      expect(Accounting::JournalEntryLine.where(lettering_id: lettering.id).sum(:debit)).to eq(Accounting::JournalEntryLine.where(lettering_id: lettering.id).sum(:credit))
    end

    it "books a gain, on the gain account, when more came in" do
      payment = pay(eur: "1000.00") # 1 000 USD at 1.00
      expect(letter(invoice_line, payment)).to be_success
      expect(fx_entry.lines.find_by(account: fx_gain)).to have_attributes(credit: BigDecimal("90.91"))
    end

    it "books nothing when the euros are the same" do
      expect(letter(invoice_line, pay(eur: "909.09"))).to be_success
      expect(fx_entry).to be_nil
    end

    it "makes an entry that the lettering generated: posted by itself, dated at the latest line, marked as the system's, linked to the lettering" do
      payment = pay(eur: "800.00")
      result = letter(invoice_line, payment)

      entry = fx_entry
      expect(entry).to be_posted
      expect(entry.entry_date).to eq(payment_day)
      expect(entry.lettering_id).to eq(result[:lettering].id)
      expect(entry.description).to start_with("FX adjustment")
      expect(entry.created_by).to be_nil
    end

    it "dates it at the latest line even when the invoice is the later one" do
      payment = pay(eur: "800.00", date: invoice_day - 3)
      letter(invoice_line, payment)
      expect(fx_entry.entry_date).to eq(invoice_day)
    end
  end

  describe "with fx_realized_as_draft" do
    before { entity.update!(fx_realized_as_draft: true) }

    it "keeps the entry as a draft, and brings its line into the lettering once someone posts it" do
      payment = pay(eur: "800.00")
      result = letter(invoice_line, payment)
      lettering = result[:lettering]

      expect(result).to be_success, result.message
      expect(fx_entry).to be_draft
      expect(fx_entry.lettering_id).to eq(lettering.id)
      expect(lettering.lines.reload.size).to eq(2)

      Accounting::PostJournalEntry.call!(entry: fx_entry, keep_reference: true)
      expect(lettering.lines.reload.size).to eq(3)
      expect(lettering.lines.sum(:debit)).to eq(lettering.lines.sum(:credit))
    end
  end

  describe "undoing the lettering (criterion 3)" do
    it "reverses the exchange difference and restores the open amounts, in USD and in EUR" do
      payment = pay(eur: "800.00")
      lettering = letter(invoice_line, payment)[:lettering]

      expect(Accounting::UnletterLines.call(lettering: lettering, reason: "Wrong payment", user: user)).to be_success

      expect(fx_entry.reload).to be_reversed
      open = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: Date.current).call
      expect(open.map(&:residual)).to contain_exactly(BigDecimal("909.09"), BigDecimal("-800.00"))
      expect(open.sum(&:residual)).to eq(BigDecimal("109.09")) # the payment and the invoice are open again, and the difference nets to nothing
      expect(Accounting::ForeignRevaluationQuery.new(as_of: Date.current).call.find { |r| r.kind == :receivable }.foreign_amount).to eq(BigDecimal("0"))
    end

    it "deletes the draft exchange difference" do
      entity.update!(fx_realized_as_draft: true)
      lettering = letter(invoice_line, pay(eur: "800.00"))[:lettering]
      Accounting::UnletterLines.call(lettering: lettering, reason: "Wrong payment", user: user)
      expect(fx_entry).to be_nil
    end
  end

  describe "a locked period" do
    it "refuses the lettering when the exchange difference falls in it, with a message that says so" do
      payment = pay(eur: "800.00")
      create(:period_lock, starts_on: payment_day.beginning_of_month, ends_on: payment_day.end_of_month)
      result = letter(invoice_line, payment)

      expect(result).to be_failure
      expect(result.message).to match(/exchange difference.*locked period/i)
      expect(fx_entry).to be_nil
      expect(invoice_line.reload.lettering_id).to be_nil
    end
  end

  describe "what is refused" do
    it "lettering two different currencies (criterion 7)" do
      zmw = pay(eur: "40.00", foreign: "1000", currency: "ZMW", rate: "25")
      result = letter(invoice_line, zmw)
      expect(result).to be_failure
      expect(result.message).to match(/USD.*ZMW|different currencies/i)
    end

    it "lettering a USD invoice with a payment in EUR, and says to book a conversion entry" do
      eur = post_entry(payment_day, bank_journal, [ bank, :debit, "900.00", nil ], [ customers, :credit, "900.00", nil ])[customers]
      result = letter(invoice_line, eur)
      expect(result).to be_failure
      expect(result.message).to match(/conversion entry/i)
    end

    it "lettering USD amounts that do not cancel out in USD, however the euros are" do
      result = letter(invoice_line, pay(eur: "909.09", foreign: "990", rate: "1.0890"))
      expect(result).to be_failure
      expect(result.message).to match(/balance in USD/i)
    end

    it "an EUR lettering that does not balance, as before" do
      a = post_entry(invoice_day, sales, [ customers, :debit, "100.00", nil ], [ revenue, :credit, "100.00", nil ])[customers]
      b = post_entry(payment_day, bank_journal, [ bank, :debit, "90.00", nil ], [ customers, :credit, "90.00", nil ])[customers]
      expect(letter(a, b)).to be_failure
    end
  end

  it "does not allocate part of a foreign line by hand: a partial payment of a foreign invoice goes through the bank reconciliation, which computes the difference" do
    payment = pay(eur: "400.00", foreign: "500")
    result = Accounting::AllocateLines.call(lines: [ invoice_line, payment ])
    expect(result).to be_failure
    expect(result.message).to match(/foreign currency.*bank reconciliation/i)
  end

  it "settles the invoice that the lettering pays" do
    invoice = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sales, status: :posted)
    invoice.update_columns(journal_entry_id: invoice_line.journal_entry_id)
    expect(letter(invoice_line, pay(eur: "800.00"))).to be_success
    expect(invoice.reload).to be_paid
  end
end
