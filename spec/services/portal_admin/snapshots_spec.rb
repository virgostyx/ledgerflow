require 'rails_helper'

# B02c, "Tableau de bord client": snapshots made by the firm's side from the books, with a whitelist of indicators, no name of a third party, a fingerprint; the client never triggers a calculation.
RSpec.describe 'Dashboard snapshots' do
  include_context 'with entity'

  let(:today)   { Date.new(2026, 5, 15) }
  let!(:fy2025) { create(:fiscal_year, year: 2025, start_date: Date.new(2025, 1, 1), end_date: Date.new(2025, 12, 31), status: :closed, entity: entity) }
  let!(:fy2026) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open, entity: entity) }
  let(:journal) { create(:journal, :purchase) }
  let!(:bank)     { create(:account, code: '550000', label_fr: 'Bank', account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:sales)    { create(:account, code: '700000', label_fr: 'Sales', account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let!(:expenses) { create(:account, code: '604000', label_fr: 'Services', account_class: 6, account_type: :expense, normal_balance: :debit) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:supplier_account) { create(:account, :supplier, reconcilable: true) }
  let(:staff) { create(:user) }

  def post_entry(fiscal_year, date, debit, credit, amount, partner: nil, invoice: nil)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: debit, partner: (partner if [ customer_account, supplier_account ].include?(debit)), invoice: (invoice if [ customer_account, supplier_account ].include?(debit)),
                                debit: BigDecimal(amount.to_s), credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: credit, partner: (partner if [ customer_account, supplier_account ].include?(credit)), invoice: (invoice if [ customer_account, supplier_account ].include?(credit)),
                                debit: 0, credit: BigDecimal(amount.to_s))
    entry.post!
  end

  before do
    post_entry(fy2025, Date.new(2025, 5, 10), bank, sales, 600)      # May last year
    post_entry(fy2026, Date.new(2026, 4, 12), bank, sales, 800)      # April
    post_entry(fy2026, Date.new(2026, 5, 3), bank, sales, 1000)      # May (this month)
    post_entry(fy2026, Date.new(2026, 5, 9), expenses, bank, 300)    # an expense
    partner = create(:partner, name: 'Secret Customer Ltd')
    invoice = create(:invoice, :posted, fiscal_year: fy2026, due_date: today - 40)
    post_entry(fy2026, Date.new(2026, 3, 1), customer_account, sales, 250, partner: partner, invoice: invoice) # overdue receivable
    supplier = create(:partner, name: 'Secret Supplier Ltd')
    supplier_invoice = create(:invoice, :posted, fiscal_year: fy2026, due_date: today + 10)
    post_entry(fy2026, Date.new(2026, 5, 1), expenses, supplier_account, 90, partner: supplier, invoice: supplier_invoice) # a payable due in 10 days
  end

  def generate(**args) = travel_to(today.in_time_zone.change(hour: 12)) { PortalAdmin::GenerateSnapshot.call(entity: entity, **args) }

  describe PortalAdmin::GenerateSnapshot do
    it 'computes the indicators of the whitelist from the books, in SQL, as numbers written as strings' do
      snapshot = generate[:snapshot]
      ind = snapshot.indicators

      expect(ind['cash']).to eq('1500.00')                # the bank of the year: 800 + 1000 - 300
      expect(ind['sales_month']).to eq('1000.00')          # May
      expect(ind['sales_previous_month']).to eq('800.00')  # April
      expect(ind['sales_last_year']).to eq('600.00')       # May of the year before, read in its own year
      expect(ind['result_ytd']).to eq('1660.00')           # sales 800 + 1000 + 250, expenses 300 + 90
    end

    it 'keeps to the whitelist and says nothing of a third party' do
      snapshot = generate[:snapshot]

      expect(snapshot.indicators.keys).to all(be_in(Portal::Snapshot::INDICATORS))
      expect(snapshot.series.keys).to all(be_in(Portal::Snapshot::SERIES))
      expect(snapshot.attributes.values.map(&:to_s).join(' ')).not_to include('Secret')
    end

    it 'gives the late receivables and the payables of the next 30 days' do
      ind = generate[:snapshot].indicators

      expect(ind['receivables_overdue']).to eq('250.00')
      expect(ind['receivables_overdue_count']).to eq(1)
      expect(ind['payables_30_days']).to eq('90.00')
    end

    it 'gives a series of the last 12 months, oldest first' do
      series = generate[:snapshot].series

      expect(series['sales'].size).to eq(12)
      expect(series['sales'].last).to include('month' => '2026-05', 'value' => '1000.00')
      expect(series['sales'].first['month']).to eq('2025-06')
      expect(series['cash'].size).to eq(12)
    end

    it 'says "provisional" while the year is not closed, and not once it is' do
      expect(generate[:snapshot].provisional).to be(true)
      fy2026.update_columns(status: Accounting::FiscalYear.statuses[:closed])
      expect(generate[:snapshot].provisional).to be(false)
    end

    it 'fingerprints what it says, and the date of the books it read' do
      snapshot = generate[:snapshot]
      expect(snapshot.sha256).to eq(Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate({ 'indicators' => snapshot.indicators, 'series' => snapshot.series })))
      expect(snapshot.known_at).to be_within(1.minute).of(today.in_time_zone.change(hour: 12))
      expect(snapshot.generated_at).to be_present
    end

    it 'is published at once, or waits for the firm when the company asks for its approval first' do
      expect(generate[:snapshot].status).to eq('published')
      entity.update!(snapshot_approval_required: true)
      expect(generate[:snapshot].status).to eq('pending_review')
    end

    it 'writes nothing in the books' do
      expect { generate }.not_to change(Accounting::JournalEntry, :count)
    end

    it 'refuses when the feature is off' do
      entity.update!(features: { 'b02c' => false })
      expect(generate).to be_failure
    end
  end

  it 'makes a snapshot of books that are empty: zeros, not an error' do
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { create(:fiscal_year, status: :open, entity: other) }
    snapshot = PortalAdmin::GenerateSnapshot.call(entity: other)[:snapshot]
    expect(snapshot.indicators).to include('cash' => '0.00', 'receivables_overdue' => '0.00', 'receivables_overdue_count' => 0)
  end

  describe PortalAdmin::ReviewSnapshot do
    let(:snapshot) { entity.update!(snapshot_approval_required: true); generate[:snapshot] }

    it 'publishes a snapshot that waited, with a trace' do
      described_class.publish(snapshot, by: staff)
      expect(snapshot.reload).to have_attributes(status: 'published', published_by_id: staff.id)
      expect(Accounting::AuditLog.where(action: 'portal_snapshot_published').count).to eq(1)
    end

    it 'shows the word of the accountant only once approved by a person' do
      published = generate[:snapshot]
      described_class.write_word(published, text: 'A good month.', source: 'human', by: staff)
      expect(published.reload.word_approved_at).to be_nil
      expect(Portal::Snapshot.shown_word(published)).to be_nil

      described_class.approve_word(published, by: staff)
      expect(Portal::Snapshot.shown_word(published.reload)).to eq('A good month.')
    end

    it 'does not show a draft written by the assistant until a person approved it, and says where it came from' do
      published = generate[:snapshot]
      described_class.write_word(published, text: 'Draft of the assistant', source: 'agent_draft', by: staff)
      expect(Portal::Snapshot.shown_word(published.reload)).to be_nil
      described_class.approve_word(published, by: staff)
      expect(published.reload.word_source).to eq('agent_draft')
      expect(Portal::Snapshot.shown_word(published)).to eq('Draft of the assistant')
    end

    it 'cleans the text, and a new text must be approved again' do
      published = generate[:snapshot]
      described_class.write_word(published, text: '<b>Hello</b> there', source: 'human', by: staff)
      described_class.approve_word(published, by: staff)
      expect(published.reload.accountant_word).to eq('Hello there')
      described_class.write_word(published, text: 'Changed', source: 'human', by: staff)
      expect(Portal::Snapshot.shown_word(published.reload)).to be_nil
    end
  end
end

# B02c: alerts the firm defined, told to the directors of the portal: the forecast cash (R14) under a threshold. A count-free message with no amount.
RSpec.describe PortalAdmin::DashboardAlerts do
  include_context 'with entity'

  let(:director) { create(:portal_user) }
  let(:colleague) { create(:portal_user) }
  let!(:bank) { create(:account, code: '550000', label_fr: 'Bank', account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:fiscal_year) { create(:fiscal_year, status: :open, entity: entity) }

  before do
    Portal::Grant.create!(portal_user: director, entity_id: entity.id, role: 'director', capabilities: %w[dashboard.view])
    Portal::Grant.create!(portal_user: colleague, entity_id: entity.id, role: 'collaborator', capabilities: %w[dashboard.view])
    ActionMailer::Base.deliveries.clear
  end

  def rule(threshold) = Portal::AlertRule.create!(entity_id: entity.id, kind: 'cash_below', threshold: threshold)

  it 'tells the directors when the forecast cash is under the threshold, once a week, without any amount' do
    rule(1_000) # the books are empty: the forecast is at 0

    described_class.call
    described_class.call

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ director.email ])
    expect(mail.body.to_s).not_to include('1000', '1,000', '€', 'EUR') # no amount (the name of the company may carry digits)
  end

  it 'says nothing when the forecast stays above the threshold' do
    rule(-1_000_000)
    described_class.call
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'alerts again the week after' do
    alert = rule(1_000)
    described_class.call
    alert.update!(last_alerted_on: Date.current - 8)
    described_class.call
    expect(ActionMailer::Base.deliveries.size).to eq(2)
  end

  it 'ignores a rule that was turned off, and a company without the feature' do
    rule(1_000).update!(active: false)
    described_class.call
    entity.update!(features: { 'b02c' => false })
    rule(1_000)
    described_class.call
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
