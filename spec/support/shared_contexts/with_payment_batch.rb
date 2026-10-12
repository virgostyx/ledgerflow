# A company with a funded bank account, a verified supplier account and helpers to post invoices and compose payment batches (B01b).
RSpec.shared_context "with payment batch" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:monday) { Time.zone.local(2026, 10, 12, 10, 0) }
  let(:execution) { Date.new(2026, 10, 14) } # a Wednesday
  let(:bank) { create(:bank_account, currency: "EUR") }
  let(:preparer) { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:authorizer) { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:owner) { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:supplier) { create(:partner, :supplier, name: "Acme Ltd", iban: nil) }
  let!(:account) { create(:partner_bank_account, :verified, partner: supplier, iban: "BE68539007547034", created_by: owner, first_seen_at: 90.days.ago) }
  let(:profile) { Payments::BankProfile.create!(name: "Test bank", format_version: "pain.001.001.03") }

  around { |example| travel_to(monday) { example.run } }

  before do
    fund(100_000)
    entity.update!(features: entity.features.merge("b01b" => true), legal_name: "Ledger Flow SRL")
  end

  def fund(amount)
    capital = create(:account, code: "100000", label_fr: "Capital", account_type: :equity, normal_balance: :credit, account_class: 1)
    entry = create(:journal_entry, :draft, journal: bank.journal, fiscal_year: fiscal_year, entry_date: Date.current - 40, reference: "FUND-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank.journal.default_account, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: capital, debit: 0, credit: amount)
    entry.post!
  end

  def posted(partner: supplier, unit_price: 1000, payment_reference: nil, due: Date.current + 3)
    invoice = create(:invoice, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, partner: partner, due_date: due, payment_reference: payment_reference)
    create(:invoice_line, invoice: invoice, account: account_604, unit_price: unit_price, quantity: 1, vat_rate: "21.00")
    Accounting::PostInvoice.call(invoice: invoice).tap { |r| raise r.message if r.failure? }
    invoice.reload
  end

  def batch_of(*invoices, date: execution, **options)
    result = Payments::ComposeBatch.call(bank_account: bank, execution_date: date, selections: invoices.map { |i| { invoice_id: i.id } }, user: preparer, **options)
    raise result.message if result.failure?

    result[:batch].tap { |b| b.update!(bank_profile: profile) }
  end
end

# The approval of a batch, as the engine does it: a policy for batches, the request, one approver.
RSpec.shared_context "with approvable batch" do
  include_context "with payment batch"

  def approved_batch(*invoices)
    batch = batch_of(*(invoices.presence || [ posted ]))
    unless Approvals::Policy.payment_batch.exists?
      Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin])
    end
    request = Payments::SubmitBatch.call(batch: batch, user: preparer)[:request]
    Approvals::Decide.call(request: request, user: authorizer, decision: :approved, content_fingerprint: request.content_fingerprint).tap { |r| raise r.message if r.failure? }
    batch.reload
  end
end
