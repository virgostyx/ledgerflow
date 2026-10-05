require "rails_helper"

# F10, step 16: the carry-forward. The opening entry of the next year, in draft, from the closing balances of classes 0 to 5; the open lines of the partners
# one by one, with their due date and their origin; the result into the carry account. Criteria 2 and 3.
RSpec.describe "Closing: carry-forward" do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:run) { Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)[:run] }
  let(:journal) { create(:journal, :sale) }
  let!(:misc) { create(:journal, journal_type: :misc, code: "OD", label_fr: "Miscellaneous") }
  let(:year_end) { fiscal_year.end_date }

  let!(:bank)      { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital)   { create(:account, code: "100000", label_fr: "Capital", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:customers) { create(:account, code: "400000", label_fr: "Customers", account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true) }
  let!(:suppliers) { create(:account, code: "440000", label_fr: "Suppliers", account_class: 4, account_type: :liability, normal_balance: :credit, reconcilable: true) }
  let!(:revenue)   { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:expense)   { create(:account, code: "604000", label_fr: "Services", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:result_account) { create(:account, code: "699000", label_fr: "Result", account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:carry_account)  { create(:account, code: "140100", label_fr: "Profit carried forward", account_class: 1, account_type: :equity, normal_balance: :credit) }
  let(:alice) { create(:partner, name: "Alice", payment_terms_days: 30) }
  let(:bob)   { create(:partner, name: "Bob", payment_terms_days: 15) }
  let(:acme)  { create(:partner, :supplier, name: "Acme", payment_terms_days: 30) }
  let!(:next_year) { create(:fiscal_year, status: :pre_closing, year: fiscal_year.year + 1, start_date: year_end + 1, end_date: ((year_end + 1) >> 12) - 1) }

  def post(date, *lines, year: fiscal_year, jr: journal)
    entry = create(:journal_entry, :draft, journal: jr, fiscal_year: year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    created = lines.map { |account, side, amount, extra| create(:journal_entry_line, { journal_entry: entry, account: account, side => amount, (side == :debit ? :credit : :debit) => 0 }.merge(extra || {})) }
    entry.post!
    created
  end

  def step(code) = Closing::Registry.fetch(code).new(run)
  def carry = step("carry_forward")
  def close_income
    step("closing_entries").perform(user: accountant)
    Closing::ValidateEntries.call(run: run, user: accountant)
  end

  let!(:alice_open) { post(fiscal_year.start_date + 20, [ customers, :debit, 600, { partner: alice } ], [ revenue, :credit, 600 ]).first }
  let!(:bob_open)   { post(fiscal_year.start_date + 40, [ customers, :debit, 250, { partner: bob } ], [ revenue, :credit, 250 ]).first }
  let!(:acme_open)  { post(fiscal_year.start_date + 50, [ expense, :debit, 300 ], [ suppliers, :credit, 300, { partner: acme } ]).last }

  before do
    post(fiscal_year.start_date + 1, [ bank, :debit, 10_000 ], [ capital, :credit, 10_000 ])
    # Bob's invoice is paid and lettered: it is not carried
    payment = post(fiscal_year.start_date + 60, [ bank, :debit, 250 ], [ customers, :credit, 250, { partner: bob } ]).last
    lettering = create(:lettering, account: customers, partner: bob)
    Accounting::JournalEntryLine.where(id: [ bob_open.id, payment.id ]).update_all(lettering_id: lettering.id)
    Accounting::JournalEntryLine.resync_amount_residual!([ bob_open.id, payment.id ])
  end

  it "waits for the closing entry: the income accounts are closed first" do
    result = carry.perform(user: accountant)
    expect(result).to be_failure
    expect(result.message).to match(/closing entr/i)
  end

  context "in a year with a loss (decided 2026-10-05: a loss goes to 140200, a profit to 140100)" do
    let!(:loss_account) { create(:account, code: "140200", label_fr: "Loss carried forward", account_class: 1, account_type: :equity, normal_balance: :debit) }

    before do
      post(fiscal_year.start_date + 80, [ expense, :debit, 2_000 ], [ bank, :credit, 2_000 ]) # 600 + 250 - 300 - 2 000: a loss of 1 450
      close_income
    end

    it "carries the loss into the loss account, as a debit, and nothing into the account of the profits" do
      entry = carry.perform(user: accountant)[:entry]
      expect(entry.lines.find_by(account: loss_account)).to have_attributes(debit: 1_450, credit: 0)
      expect(entry.lines.where(account: carry_account)).to be_empty
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it "reads back as correct once validated: opening balances against closing balances" do
      carry.perform(user: accountant)
      Closing::ValidateEntries.call(run: run, user: accountant)
      expect(carry.evaluate.status).to eq(:ok)
    end

    it "carries the loss into the carry account itself when the chart has no loss account (a debit balance on it)" do
      entity.update!(closing_loss_account_code: "999999")
      run.reload # (the run keeps the entity it read)
      entry = carry.perform(user: accountant)[:entry]
      expect(entry.lines.find_by(account: carry_account)).to have_attributes(debit: 1_450, credit: 0)
      Closing::ValidateEntries.call(run: run, user: accountant)
      expect(carry.evaluate.status).to eq(:ok)
    end
  end

  context "once the income accounts are closed" do
    before { close_income }

    it "drafts one balanced entry in the next year, at its first day, tagged with the run, validating nothing" do
      result = carry.perform(user: accountant)
      expect(result).to be_success, result.message
      entry = result[:entry]

      expect(entry).to be_draft
      expect(entry).to have_attributes(fiscal_year_id: next_year.id, entry_date: next_year.start_date, closing_run_id: run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE)
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it "carries the open lines of the partners one by one, with partner, amount, due date, label and origin, and not the one that was lettered" do
      entry = carry.perform(user: accountant)[:entry]
      lines = entry.lines.where(account: customers)

      expect(lines.count).to eq(1)
      expect(lines.sole).to have_attributes(partner_id: alice.id, debit: 600, credit: 0, origin_line_id: alice_open.id, due_date: alice_open.journal_entry.entry_date + 30)
      expect(lines.sole.label).to match(/carry-forward/i)
      expect(entry.lines.where(account: suppliers).sole).to have_attributes(partner_id: acme.id, credit: 300, origin_line_id: acme_open.id)
    end

    it "carries only what is left of a line that is partly allocated" do
      payment = post(fiscal_year.start_date + 70, [ bank, :debit, 100 ], [ customers, :credit, 100, { partner: alice } ]).last
      Accounting::LineAllocation.create!(debit_line: alice_open, credit_line: payment, amount: 100, allocated_on: fiscal_year.start_date + 70)
      Accounting::JournalEntryLine.resync_amount_residual!([ alice_open.id, payment.id ])

      lines = carry.perform(user: accountant)[:entry].lines.where(account: customers)
      expect(lines.map { |l| [ l.origin_line_id, l.debit, l.credit ] }).to contain_exactly([ alice_open.id, 500, 0 ])
    end

    it "carries the other balance sheet accounts as one line each, and the result into the carry account, nothing for the income accounts" do
      entry = carry.perform(user: accountant)[:entry]

      expect(entry.lines.find_by(account: bank)).to have_attributes(debit: 10_000 + 250, credit: 0) # the bank, with Bob's payment
      expect(entry.lines.find_by(account: capital)).to have_attributes(credit: 10_000)
      expect(entry.lines.find_by(account: carry_account).credit).to eq(600 + 250 - 300) # the profit of the year
      expect(entry.lines.where(account: [ revenue, expense, result_account ])).to be_empty
    end

    it "makes only one entry however many times it is asked, and validates nothing by itself" do
      first = carry.perform(user: accountant)[:entry]
      expect { carry.perform(user: accountant) }.not_to change(Accounting::JournalEntry, :count)
      expect(carry.perform(user: accountant)[:entry]).to eq(first)
      expect(Accounting::JournalEntry.where(closing_run_id: run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE).pluck(:status)).to eq([ "draft" ])
    end

    it "refuses when the carry account does not exist, naming it" do
      carry_account.destroy!
      result = carry.perform(user: accountant)
      expect(result).to be_failure
      expect(result.message).to include("140100")
    end

    it "refuses when the next year does not exist" do
      next_year.destroy!
      expect(carry.perform(user: accountant)).to be_failure
    end

    describe "after the batch validation" do
      before do
        carry.perform(user: accountant)
        Closing::ValidateEntries.call(run: run, user: accountant)
      end

      it "gives the next year the closing balances of classes 0 to 5 as its opening balances; the income accounts open at zero (criterion 2)" do
        closing = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call.index_by(&:code)
        opening = Accounting::TrialBalanceQuery.new(fiscal_year: next_year, as_of: next_year.start_date).call.index_by(&:code)

        %w[550000 100000 400000 440000].each { |code| expect(opening[code].closing_net).to eq(closing[code].closing_net), code }
        expect(opening["140100"].closing_net).to eq(closing["699000"].closing_net) # the result, a credit
        expect(opening.keys & %w[700000 604000 699000]).to eq([])
      end

      it "gives the same aged balance on the first day of the new year as on the last day of the old, partner by partner (criterion 3)" do
        %i[customer supplier].each do |kind|
          before = Accounting::AgedBalanceQuery.new(kind: kind, as_of: year_end).call.to_h { |r| [ r.partner_name, r.total ] }
          after  = Accounting::AgedBalanceQuery.new(kind: kind, as_of: next_year.start_date).call.to_h { |r| [ r.partner_name, r.total ] }
          expect(after).to eq(before)
        end
      end

      it "is ok, verified" do
        expect(carry.evaluate).to have_attributes(status: :ok)
      end

      it "is blocked if the opening balance of a partner account no longer matches" do
        Accounting::JournalEntryLine.where(journal_entry_id: Accounting::JournalEntry.find_by(closing_run_id: run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE)).where(account: bank).update_all(debit: 1)
        expect(carry.evaluate).to have_attributes(status: :blocked)
      end
    end

    it "is pending while the entry is a draft" do
      carry.perform(user: accountant)
      result = carry.evaluate
      expect(result).to have_attributes(status: :pending)
      expect(result.details).to include("draft_entry_id" => be_a(Integer))
    end
  end

  it "carries a line in a foreign currency with its share of the amount in currency, the currency and the rate" do
    usd = post(fiscal_year.start_date + 30, [ customers, :debit, 909.09, { partner: alice, currency: "USD", amount_currency: 1000, exchange_rate: BigDecimal("1.1") } ],
               [ revenue, :credit, 909.09, { currency: "USD", amount_currency: -1000, exchange_rate: BigDecimal("1.1") } ]).first
    close_income
    line = carry.perform(user: accountant)[:entry].lines.find_by(origin_line_id: usd.id)

    expect(line).to have_attributes(debit: BigDecimal("909.09"), currency: "USD", amount_currency: BigDecimal("1000"), exchange_rate: BigDecimal("1.1"))
  end

  it "warns of an archived partner that still has open lines: they are carried as they stand" do
    close_income
    alice.update!(active: false)
    carry.perform(user: accountant)
    Closing::ValidateEntries.call(run: run, user: accountant)

    expect(carry.evaluate).to have_attributes(status: :warning)
    expect(carry.evaluate.details["archived_partners"]).to eq([ "Alice" ])
  end
end
