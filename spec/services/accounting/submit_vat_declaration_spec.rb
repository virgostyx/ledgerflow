require "rails_helper"

# F01 + R09: a filed VAT period is locked through the period locks (no parallel mechanism): nothing can be posted
# inside it afterwards, a regularisation goes in the next period.
RSpec.describe Accounting::SubmitVatDeclaration do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let(:period_start) { fiscal_year.start_date }
  let(:period_end)   { fiscal_year.start_date.end_of_month }
  let(:declaration) do
    create(:vat_declaration, fiscal_year: fiscal_year, status: :draft, period_type: :monthly, period_start: period_start, period_end: period_end)
  end

  def entry_on(date) = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: date)

  it "submits the declaration and locks its period (kind VAT), saying who and why" do
    result = described_class.call(declaration: declaration, user: user)

    expect(result).to be_success
    expect(declaration.reload).to be_submitted
    lock = Accounting::PeriodLock.vat.sole
    expect(lock).to have_attributes(starts_on: period_start, ends_on: period_end, locked_by: user)
    expect(lock).to be_locked
    expect(lock.lock_reason).to include("VAT declaration", period_start.to_s)
    expect(Accounting::AuditLog.where(action: "lock_period", auditable_id: lock.id)).to be_present
  end

  it "refuses to post an entry dated inside the filed period, manual entries included" do
    described_class.call(declaration: declaration, user: user)

    result = Accounting::PostJournalEntry.call(entry: entry_on(period_start + 3))

    expect(result).to be_failure
    expect(result.message).to match(/locked/i)
  end

  it "accepts an entry dated the day after the filed period" do
    described_class.call(declaration: declaration, user: user)

    expect(Accounting::PostJournalEntry.call(entry: entry_on(period_end + 1))).to be_success
  end

  it "does nothing to a declaration that is not a draft" do
    declaration.update!(status: :submitted)

    result = described_class.call(declaration: declaration, user: user)

    expect(result).to be_failure
    expect(Accounting::PeriodLock.count).to eq(0)
  end

  it "keeps the declaration a draft when the period cannot be locked" do
    allow(Accounting::LockPeriod).to receive(:call).and_return(LightService::Context.make.tap { |c| c.fail!("nope") })

    result = described_class.call(declaration: declaration, user: user)

    expect(result).to be_failure
    expect(declaration.reload).to be_draft
  end

  it "leaves an owner free to unlock the period later, with a reason (the declaration stays submitted)" do
    described_class.call(declaration: declaration, user: user)

    Accounting::UnlockPeriod.call(lock: Accounting::PeriodLock.vat.sole, user: user, reason: "Correction agreed with the VAT office")

    expect(declaration.reload).to be_submitted
    expect(Accounting::PostJournalEntry.call(entry: entry_on(period_start + 3))).to be_success
  end
end
