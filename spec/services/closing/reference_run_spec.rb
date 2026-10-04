require "rails_helper"

# F10, criterion 1 and the invariants before and after: the closing of 2026 on the reference ledger, from step 1 to step 18. What the accountant does before the
# closing starts (freezing the bank reconciliations, filing the VAT, correcting the suspense account, entering the closing rates) is done here as a person does it;
# then the steps run with no intervention but the manual ones, the acknowledgement of a warning, the validation of the entries and the approval.
RSpec.describe "Closing the reference ledger", type: :invariant do
  include ActiveJob::TestHelper

  let!(:entity) { Seeders::ReferenceLedgerSeeder.call }

  def in_entity(&block) = ActsAsTenant.with_tenant(entity, &block)

  def make_users
    owner = User.create!(full_name: "Owner", email: "ref-owner@firm.test", password: SecureRandom.hex(16), role: :admin)
    accountant = User.create!(full_name: "Accountant", email: "ref-accountant@firm.test", password: SecureRandom.hex(16), role: :accountant)
    UserEntity.create!(user: owner, entity: entity, role: :admin, active: true)
    UserEntity.create!(user: accountant, entity: entity, role: :accountant, active: true)
    [ owner, accountant ]
  end

  # What is done before the closing starts.
  def make_ready(fiscal_year, owner)
    year_end = fiscal_year.end_date
    Accounting::BankAccount.find_each do |account|
      result = Accounting::BankReconciliationQuery.new(bank_account: account, as_of: year_end).call
      Accounting::BankReconciliationReport.record!(bank_account: account, as_of: year_end, user: owner, result: { gap: result.gap.to_s })
    end
    # the lettering fixtures leave a balance on the suspense account: a person corrects it
    suspense = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call.find { |r| r.code == "499000" }&.balance.to_d
    unless suspense.zero?
      entry = Accounting::JournalEntry.create!(journal: Accounting::Journal.find_by!(code: "OD"), fiscal_year: fiscal_year, entry_date: Date.current, description: "Suspense cleared", status: :draft)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry.lines.create!(account: Accounting::Account.find_by!(code: "499000"), label: "Suspense cleared", debit: suspense.negative? ? suspense.abs : 0, credit: suspense.positive? ? suspense : 0)
      entry.lines.create!(account: Accounting::Account.find_by!(code: "658100"), label: "Suspense cleared", debit: suspense.positive? ? suspense : 0, credit: suspense.negative? ? suspense.abs : 0)
      Accounting::PostJournalEntry.call!(entry: entry)
    end
    4.times do |i|
      from = fiscal_year.start_date >> (3 * i)
      to = (from >> 3) - 1
      generated = Accounting::GenerateVatReturn.call(fiscal_year_id: fiscal_year.id, period_start: from, period_end: to, period_type: :quarterly)
      raise generated.message if generated.failure?

      submitted = Accounting::SubmitVatDeclaration.call(declaration: generated[:vat_declaration], user: owner)
      raise submitted.message if submitted.failure?
    end
    { "USD" => "1.0", "ZMW" => "25" }.each { |currency, rate| Accounting::ExchangeRate.create!(currency: currency, rate_date: year_end, rate: rate, rate_type: :closing, source: "manual") }
  end

  def balances(fiscal_year, as_of) = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: as_of).call.index_by(&:code)

  it "closes 2026 from step 1 to step 18, and the invariants hold before and after" do
    in_entity do
      owner, accountant = make_users
      fiscal_year = Accounting::FiscalYear.find_by!(year: 2026)
      make_ready(fiscal_year, owner)
      year_end = fiscal_year.end_date

      aged_before = %i[customer supplier].to_h { |kind| [ kind, Accounting::AgedBalanceQuery.new(kind: kind, as_of: year_end).call.to_h { |r| [ r.partner_name, r.total ] } ] }
      closing_before = balances(fiscal_year, year_end)

      run = Closing::OpenRun.call(fiscal_year: fiscal_year, user: accountant)[:run]
      perform = lambda do |code|
        result = Closing::PerformStep.call(run: run, code: code, user: accountant)
        expect(result).to be_success, "#{code}: #{result.message}"
      end
      statuses = -> { Closing::Evaluate.call(run: run); run.steps.reload.to_h { |s| [ s.code, s.status ] } }

      %w[preparation fixed_assets accruals revaluation].each { |code| perform.(code) }
      expect(Accounting::JournalEntry.where(closing_run_id: run.id, status: :draft).count).to be >= 1 # the revaluation (the regularization of the reference ledger was booked and validated already)

      # VAT locks the last quarter: an owner opens the controlled window for the closing (F01), then the entries are validated in a batch, step by step
      expect(Accounting::OpenControlledWindow.call(user: owner, reason: "Closing 2026", purpose: "closing", hours: 4)).to be_success
      expect(Closing::ValidateEntries.call(run: run, user: accountant)).to be_success
      perform.("closing_entries")
      expect(Closing::ValidateEntries.call(run: run, user: accountant)).to be_success

      perform.("carry_forward")
      expect(Closing::ValidateEntries.call(run: run, user: accountant)).to be_success
      expect(statuses.call.slice("closing_entries", "carry_forward").values).to all(satisfy { |s| %w[ok done].include?(s) })

      # the one warning left, R19's numbering gap of the reference ledger, is acknowledged; the manual steps are confirmed; the review commented
      consistency = run.steps.find_by(code: "consistency")
      Closing::Evaluate.call(run: run)
      expect(consistency.reload.status).to eq("warning"), Accounting::ConsistencyFinding.where(run_id: consistency.result["run_id"], severity: %w[blocking warning]).map { |f| "#{f.check_id} #{f.severity} #{f.message}" }.join(" | ")
      expect(Closing::AcknowledgeStep.call(step: consistency, user: accountant, comment: "Gaps in the OD numbering known: reference data")).to be_success
      %w[stock provisions taxes].each { |code| expect(Closing::ConfirmStep.call(step: run.steps.find_by(code: code), user: accountant, comment: "Nothing to book")).to be_success }
      review = Closing::Steps::AnalyticalReview.new(run)
      review.evaluate.details["flagged"].each { |f| expect(review.comment(user: accountant, code: f["code"], text: "First full year of activity")).to be_success }

      perform.("lock_and_bundle")
      expect(statuses.call.except("approval").reject { |_, s| %w[ok done skipped warning].include?(s) }).to eq({}), run.steps.reload.map { |s| [ s.code, s.status, s.result ] }.inspect

      approval = Closing::Approve.call(run: run, user: owner, comment: "Approved")
      expect(approval).to be_success, approval.message
      expect(run.reload).to be_closed
      expect(fiscal_year.reload).to be_closed

      next_year = Accounting::FiscalYear.find_by!(start_date: year_end + 1)
      expect(next_year).to be_open

      # criterion 2: opening = closing for classes 0 to 5, income accounts open at zero
      opening = balances(next_year, next_year.start_date)
      closing_after = balances(fiscal_year, year_end)
      classes = Accounting::Account.where(code: closing_after.keys | opening.keys).to_h { |a| [ a.code, a.account_class ] }
      closing_after.each do |code, row|
        next unless (0..5).cover?(classes[code]) && code != "130000"

        expect(opening[code]&.closing_net.to_d).to eq(row.closing_net), "#{code}: closing #{row.closing_net}, opening #{opening[code]&.closing_net}"
      end
      expect(opening.select { |code, _| %w[6 7].include?(classes[code].to_s) }.values.map(&:closing_net).uniq - [ 0 ]).to eq([])

      # criterion 3: R04 on the first day of the new year is R04 of the last day of the old, partner by partner
      %i[customer supplier].each do |kind|
        after = Accounting::AgedBalanceQuery.new(kind: kind, as_of: next_year.start_date).call.to_h { |r| [ r.partner_name, r.total ] }
        expect(after).to eq(aged_before[kind]), kind.to_s
      end

      # criterion 9: the snapshot reads back identical
      expect(run.snapshot).to be_intact
      expect(Accounting::ClosingSnapshot.find(run.snapshot.id).sha256).to eq(run.snapshot.sha256)

      # the invariants after: I1, I2, I4 on the new year, I6 (no balance sheet gap) and the year closed
      lines = Accounting::JournalEntryLine.all
      expect(lines.sum(:debit)).to eq(lines.sum(:credit))
      expect(Accounting::AnnualAccounts.new(fiscal_year: fiscal_year).call).to be_balanced
      { customer: "400000", supplier: "440000" }.each do |kind, code|
        aged = Accounting::AgedBalanceQuery.totals(Accounting::AgedBalanceQuery.new(kind: kind, as_of: next_year.start_date).call).total
        expect(aged).to eq(balances(next_year, next_year.start_date)[code]&.balance || 0)
      end
      expect(closing_before.keys - closing_after.keys).to eq([]) # no account vanished from the old year's books
    end
  end
end
