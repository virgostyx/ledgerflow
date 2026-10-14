require "rails_helper"

# B03b R21, the other categories of the chronological detail: lettering, setup (master data), locks, documents, payments, IBAN. Only what happened between T1 and T2.
RSpec.describe Changes::Events do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let(:t1) { instant }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def events(from, to, **opts) = described_class.call(from: from, to: to, **opts)

  def audit(action, reason: nil, subject: fiscal_year) = Accounting::AuditLog.record!(auditable: subject, action: action, user: user, reason: reason)

  it "lists the letterings and unletterings with their reason" do
    from = instant
    Accounting::LetteringEvent.record!(lines: [ Struct.new(:id).new(1) ], action: "letter", code: "AA", user: user, lettered_on: Date.current)
    Accounting::LetteringEvent.record!(lines: [ Struct.new(:id).new(1) ], action: "unletter", code: "AA", user: user, reason: "wrong match")
    to = instant

    list = events(from, to).select { |e| e.category == :lettering }

    expect(list.map(&:action)).to eq(%w[letter unletter])
    expect(list.last).to have_attributes(reason: "wrong match", actor_id: user.id)
  end

  it "lists a changed or created account, and not the ones that did not change" do
    create(:account, code: "111111", account_class: 1, account_type: :equity, normal_balance: :credit)
    from = instant
    account = create(:account, code: "604500", label_fr: "Services", account_class: 6, account_type: :expense, normal_balance: :debit)
    account.update!(label_fr: "Services divers")
    to = instant

    setup = events(from, to).select { |e| e.category == :setup }

    expect(setup.map(&:subject_id).uniq).to eq([ account.id ])
    expect(setup.size).to eq(2)
    expect(setup.last.detail).to include("label_fr" => "Services divers")
  end

  it "lists the locks and the unlocks with their reason" do
    from = instant
    lock = Accounting::LockPeriod.call(starts_on: fiscal_year.start_date, ends_on: fiscal_year.start_date + 30, user: user, reason: "month closed")[:lock]
    Accounting::UnlockPeriod.call(lock: lock, user: user, reason: "forgotten invoice", notify: false)
    to = instant

    list = events(from, to).select { |e| e.category == :locks }

    expect(list.map(&:action)).to eq(%w[lock_period unlock_period])
    expect(list.map(&:reason)).to eq([ "month closed", "forgotten invoice" ])
  end

  it "lists the documents, the payments and the changes of IBAN each in its own category" do
    from = instant
    audit("document_upload")
    audit("document_archive")
    audit("payment_batch_exported")
    audit("payment_returned", reason: "returned")
    audit("bank_account_changed")
    to = instant

    by = events(from, to).group_by(&:category).transform_values { |l| l.map(&:action) }

    expect(by).to include(documents: %w[document_upload document_archive], payments: %w[payment_batch_exported payment_returned], iban: %w[bank_account_changed])
  end

  it "leaves out what happened before T1 or after T2, and the actions that are not changes (a login, a read)" do
    audit("document_upload")
    from = instant
    audit("login")
    audit("historical_view")
    audit("document_link")
    to = instant
    audit("document_archive")

    expect(events(from, to).map(&:action)).to eq([ "document_link" ])
  end

  it "keeps only the categories asked for" do
    from = instant
    audit("document_upload")
    audit("bank_account_changed")
    to = instant

    expect(events(from, to, categories: %i[iban]).map(&:category).uniq).to eq([ :iban ])
  end

  it "keeps the actor of an event whose account was deleted" do
    from = instant
    ghost = create(:user)
    Accounting::AuditLog.record!(auditable: fiscal_year, action: "document_upload", user: ghost)
    to = instant
    ghost.destroy

    expect(events(from, to).first.actor_id).to eq(ghost.id)
  end
end
