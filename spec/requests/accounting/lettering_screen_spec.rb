require "rails_helper"

# F04 §7, screens: reason and cross-partner option, filters, rounding button, suggestions panel (one click and batch with a preview),
# lettering code and history on the general ledger.
RSpec.describe "Lettering screen (F04)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:supplier) { create(:partner, :supplier, name: "Alpha Supplies") }
  let(:other)    { create(:partner, :supplier, name: "Beta Trading") }
  let(:journal)  { create(:journal, :cash) }
  let!(:misc)    { create(:journal, journal_type: :misc) }
  let!(:loss)    { create(:account, code: "658100", label_fr: "Rounding (charge)", account_class: 6, entity: entity) }
  let!(:gain)    { create(:account, code: "758100", label_fr: "Rounding (income)", account_class: 7, entity: entity) }

  def line(debit: 0, credit: 0, partner: supplier, date: fiscal_year.start_date + 20, communication: nil)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year, entry_date: date)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:bank_transaction, journal_entry: entry, structured_communication: communication) if communication
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: partner,
                                  debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  before { sign_in accountant }

  describe "cross-partner lettering" do
    it "offers the option and the reason to someone who has the right" do
      get new_accounting_lettering_path(account_id: account_440.id)

      expect(response.body).to include("cross_partner").and include("Reason")
    end

    it "letters lines of two partners when the option and a reason are given" do
      a = line(credit: 50)
      b = line(debit: 50, partner: other)

      post accounting_letterings_path, params: { account_id: account_440.id, line_ids: [ a.id, b.id ], cross_partner: "1", reason: "wrong partner on the payment" }

      expect(a.reload.lettering_id).to be_present
      expect(Accounting::Lettering.find(a.lettering_id)).to have_attributes(partner_id: nil, reason: "wrong partner on the payment")
    end
  end

  describe "filters" do
    let!(:old_line)   { line(credit: 500, date: Date.current - 90) }
    let!(:small_line) { line(credit: 20, partner: other, date: Date.current - 2) }

    def listed(**params)
      get new_accounting_lettering_path(account_id: account_440.id, **params)
      [ old_line, small_line ].select { |l| response.body.include?("line_ids_#{l.id}") }
    end

    it("by partner") { expect(listed(partner_id: other.id)).to eq([ small_line ]) }
    it("by minimum amount") { expect(listed(min_amount: 100)).to eq([ old_line ]) }
    it("by maximum amount") { expect(listed(max_amount: 100)).to eq([ small_line ]) }
    it("by age in days") { expect(listed(older_than: 30)).to eq([ old_line ]) }

    it "by state: partly settled" do
      Accounting::AllocateLines.call(lines: [ old_line, line(debit: 200) ])

      expect(listed(state: "partly")).to eq([ old_line ])
      expect(listed(state: "open")).to eq([ small_line ])
    end
  end

  describe "the rounding button" do
    let!(:invoice_line) { line(credit: 100.00) }
    let!(:payment)      { line(debit: 99.97) }

    it "books the rounding entry as a draft and goes to it" do
      expect {
        post accounting_lettering_write_offs_path, params: { account_id: account_440.id, line_ids: [ invoice_line.id, payment.id ] }
      }.to change(Accounting::LetteringWriteOff, :count).by(1)

      expect(response).to redirect_to(accounting_journal_entry_path(Accounting::LetteringWriteOff.last.journal_entry))
    end

    it "says why it refuses" do
      big = line(debit: 90.00)
      post accounting_lettering_write_offs_path, params: { account_id: account_440.id, line_ids: [ invoice_line.id, big.id ] }

      expect(response).to redirect_to(new_accounting_lettering_path(account_id: account_440.id))
      expect(flash[:alert]).to include("tolerance")
    end

    it "is offered on the screen with the tolerance" do
      get new_accounting_lettering_path(account_id: account_440.id)

      expect(response.body).to include("rounding").and include('data-lettering-total-tolerance-value="0.05"')
    end
  end

  describe "the suggestions panel" do
    let!(:invoice_line) { line(credit: 121, date: Date.current - 5) }
    let!(:payment)      { line(debit: 121, communication: "x") }
    let(:suggestion)    { Accounting::LetteringSuggestion.proposed.sole }

    before { Accounting::SuggestLetterings.call }

    it "lists them with score and rule" do
      get new_accounting_lettering_path(account_id: account_440.id)

      expect(response.body).to include("Suggestions").and include("90").and include(accept_accounting_lettering_suggestion_path(suggestion))
    end

    it "refreshes them on demand" do
      Accounting::LetteringSuggestion.delete_all

      post accounting_lettering_suggestions_path, params: { account_id: account_440.id }

      expect(Accounting::LetteringSuggestion.proposed.count).to eq(1)
      expect(response).to redirect_to(new_accounting_lettering_path(account_id: account_440.id))
    end

    it "accepts one in one click" do
      post accept_accounting_lettering_suggestion_path(suggestion)

      expect(invoice_line.reload.lettering_id).to be_present
      expect(suggestion.reload).to be_accepted
    end

    it "rejects one" do
      post reject_accounting_lettering_suggestion_path(suggestion)

      expect(suggestion.reload).to be_rejected
      get new_accounting_lettering_path(account_id: account_440.id)
      expect(response.body).not_to include(accept_accounting_lettering_suggestion_path(suggestion))
    end

    it "shows a preview before a batch, which letters nothing" do
      post preview_accounting_lettering_suggestions_path, params: { suggestion_ids: [ suggestion.id ] }

      expect(response.body).to include("Confirm")
      expect(invoice_line.reload.lettering_id).to be_nil
    end

    it "letters the batch once confirmed" do
      post accept_batch_accounting_lettering_suggestions_path, params: { suggestion_ids: [ suggestion.id ] }

      expect(invoice_line.reload.lettering_id).to be_present
      expect(flash[:notice]).to include("1")
    end

    it "reports the ones of a batch that no longer hold" do
      Accounting::LetterLines.call(lines: [ invoice_line, payment ])
      post accept_batch_accounting_lettering_suggestions_path, params: { suggestion_ids: [ suggestion.id ] }

      expect(flash[:alert]).to be_present
    end
  end

  describe "general ledger" do
    it "links the lettering code to its history" do
      a = line(credit: 50)
      b = line(debit: 50)
      lettering = Accounting::LetterLines.call(lines: [ a, b ], user: accountant)[:lettering]
      Accounting::UnletterLines.call(lettering: lettering, reason: "oops", user: accountant)
      second = Accounting::LetterLines.call(lines: [ a.reload, b.reload ], user: accountant)[:lettering]

      get accounting_reports_general_ledger_path(fiscal_year_id: fiscal_year.id, account_id: account_440.id)
      expect(response.body).to include(accounting_lettering_path(second))

      get accounting_lettering_path(second)
      expect(response.body).to include(second.code).and include("oops").and include("unletter")
    end
  end
end
