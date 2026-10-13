require "rails_helper"

# B01b §5 "Approbation du lot": the engine of B01a applies to a payment batch. Thresholds on the total and the number of payments, the levels,
# and the separation of tasks: the preparer does not authorize their own batch, nor (by option) the person who gave the approval of its invoices.
RSpec.describe "Approval of a payment batch" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:monday) { Time.zone.local(2026, 10, 12, 10, 0) }
  let(:bank) { create(:bank_account, currency: "EUR") }
  let(:preparer) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:authorizer) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:owner) { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:reader) { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:supplier) { create(:partner, :supplier, name: "Acme Ltd", iban: nil) }
  let!(:account) { create(:partner_bank_account, :verified, partner: supplier, iban: "BE68539007547034", created_by: owner, first_seen_at: 90.days.ago) }

  around { |example| travel_to(monday) { example.run } }

  before do
    fund(100_000)
    entity.update!(features: entity.features.merge("b01b" => true))
  end

  def fund(amount)
    capital = create(:account, code: "100000", label_fr: "Capital", account_type: :equity, normal_balance: :credit, account_class: 1)
    entry = create(:journal_entry, :draft, journal: bank.journal, fiscal_year: fiscal_year, entry_date: Date.current - 40, reference: "FUND-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank.journal.default_account, debit: amount, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: capital, debit: 0, credit: amount)
    entry.post!
  end

  def posted(unit_price: 1000)
    invoice = create(:invoice, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, partner: supplier, due_date: Date.current + 3)
    create(:invoice_line, invoice: invoice, account: account_604, unit_price: unit_price, quantity: 1, vat_rate: "21.00")
    Accounting::PostInvoice.call(invoice: invoice).tap { |r| raise r.message if r.failure? }
    invoice.reload
  end

  def batch_of(*invoices)
    result = Payments::ComposeBatch.call(bank_account: bank, execution_date: Date.new(2026, 10, 14), selections: invoices.map { |i| { invoice_id: i.id } }, user: preparer)
    raise result.message if result.failure?

    result[:batch].tap { |b| b.update!(bank_profile: profile) } # the format of the file comes from the bank
  end

  def policy!(conditions: {}, **step)
    Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1, conditions: conditions).tap do |policy|
      policy.steps.create!({ position: 1, mode: :any_of, approver_roles: %w[accountant admin] }.merge(step))
    end
  end

  let(:profile) { Payments::BankProfile.create!(name: "Test bank", format_version: "pain.001.001.03") }
  let(:batch) { batch_of(posted) } # 1 210.00 incl. VAT, 1 payment

  def submit(batch = self.batch, user: preparer) = Payments::SubmitBatch.call(batch: batch, user: user)

  def decide(request, user, decision = :approved, **extra)
    Approvals::Decide.call(request: request, user: user, decision: decision, content_fingerprint: request.content_fingerprint, **extra)
  end

  def audit(action) = Accounting::AuditLog.for_record(batch).for_action(action)

  describe "the policy that applies" do
    it "is chosen on the total and the number of payments, among the policies of payment batches only" do
      big_batch = batch
      small_batch = batch_of(posted(unit_price: 100))
      Approvals::Policy.create!(name: "an invoice policy", subject: :purchase_invoice, priority: 0)
      small = policy!(conditions: { "max_amount" => "1000" })
      big = policy!(conditions: { "min_amount" => "1000.01", "max_payments" => 5 })

      expect(Approvals::PolicyMatcher.call(big_batch)).to eq(big)
      expect(Approvals::PolicyMatcher.call(small_batch)).to eq(small)
    end

    it "does not match a batch with more payments than the policy allows" do
      policy!(conditions: { "min_payments" => 2 })

      expect(Approvals::PolicyMatcher.call(batch)).to be_nil
    end
  end

  describe "submitting a batch" do
    it "opens the request on the fingerprint of the batch, puts the batch to approval and says so in the audit trail" do
      policy = policy!
      result = submit

      expect(result).to be_success
      request = result[:request]
      expect(request).to be_pending
      expect(request.policy).to eq(policy)
      expect(request.content_fingerprint).to eq(Approvals::ContentFingerprint.call(batch))
      expect(batch.reload).to be_pending_approval
      expect(batch.approval_request).to eq(request)
      expect(audit("approval_submitted").count).to eq(1)
    end

    it "is idempotent on the same content" do
      policy!

      expect { 2.times { submit } }.to change(Approvals::Request, :count).by(1)
    end

    it "refuses a batch that no policy covers: nobody authorizes a payment by default" do
      result = submit

      expect(result).to be_failure
      expect(result.message).to match(/policy/i)
      expect(batch.reload).to be_draft
    end

    it "refuses a batch without a bank profile that names a version the builder knows: the format is not guessed" do
      policy!
      batch.update!(bank_profile: nil)
      expect(submit).to be_failure

      batch.update!(bank_profile: Payments::BankProfile.create!(name: "Other", format_version: "pain.001.001.09"))
      expect(submit).to be_failure
      expect(submit.message).to match(/format|version/i)
      expect(batch.reload).to be_draft
    end

    it "refuses a batch whose pre-flight has an error" do
      policy!
      batch
      account.update_columns(status: Accounting::PartnerBankAccount.statuses[:blocked])

      expect(submit).to be_failure
      expect(batch.reload).to be_draft
    end

    it "refuses a batch whose warnings nobody acknowledged" do
      policy!
      allow(Payments::Preflight).to receive(:call).and_wrap_original do |original, b|
        original.call(b).tap { |report| report.warnings << Payments::Preflight::Finding.new(code: :low_balance, key: "low_balance:x", message: "Low") }
      end

      expect(submit).to be_failure
    end

    it "refuses when the feature is off" do
      policy!
      batch
      entity.update!(features: entity.features.merge("b01b" => false))

      expect(submit).to be_failure
    end

    it "does not take a person without the right to prepare" do
      policy!

      expect(submit(user: reader)).to be_failure
    end
  end

  describe "deciding" do
    before { policy! }

    let(:request) { submit[:request] }

    it "approves the batch, with the fingerprint seen, and makes it ready to export" do
      result = decide(request, authorizer, channel: :web)

      expect(result).to be_success
      expect(request.reload).to be_approved
      expect(batch.reload).to be_approved
      expect(audit("approval_approved").count).to eq(1)
    end

    it "does not let the person who prepared the batch authorize it" do
      result = decide(request, preparer)

      expect(result).to be_failure
      expect(result[:code]).to eq(:own_batch)
      expect(batch.reload).to be_pending_approval
    end

    it "lets them when the owner turned the option off" do
      entity.update!(distinct_payment_authorizer: false)

      expect(decide(request, preparer)).to be_success
    end

    it "refuses and asks for changes with a reason, and takes the batch back to a draft" do
      expect(decide(request, authorizer, :rejected)).to be_failure # a reason is required

      expect(decide(request, authorizer, :rejected, comment: "Wrong supplier")).to be_success
      expect(request.reload).to be_rejected
      expect(batch.reload).to be_draft
    end

    it "does not decide on a batch that changed since the approver saw it" do
      stale = request.content_fingerprint
      batch.update_columns(total: batch.total + 1)

      result = Approvals::Decide.call(request: request, user: authorizer, decision: :approved, content_fingerprint: stale)

      expect(result).to be_failure
      expect(result[:code]).to eq(:content_changed)
    end

    it "asks for a second factor above the threshold of the entity" do
      entity.update!(step_up_threshold: 1000)

      refused = decide(request, authorizer)
      expect(refused[:code]).to eq(:step_up_required)
      expect(decide(request, authorizer, recent_second_factor: true)).to be_success
    end
  end

  describe "the person who gave the approval of the invoices" do
    let(:invoice) { posted }
    let(:batch) { batch_of(invoice) }

    before do
      policy!
      entity.update!(features: entity.features.merge("b01a" => true))
      invoice_request = Approvals::Request.create!(subject: invoice, policy: Approvals::Policy.create!(name: "i", subject: :purchase_invoice), status: :approved,
                                                   content_fingerprint: Approvals::ContentFingerprint.call(invoice))
      invoice_request.decisions.create!(step_position: 1, approver: authorizer, decision: :approved, content_fingerprint: invoice_request.content_fingerprint)
    end

    it "may authorize the batch by default" do
      expect(decide(submit[:request], authorizer)).to be_success
    end

    it "may not when the owner asked for it, but another person may" do
      entity.update!(authorizer_not_bap_giver: true)
      request = submit[:request]

      refused = decide(request, authorizer)
      expect(refused[:code]).to eq(:gave_the_approval)
      expect(decide(request, owner)).to be_success
    end
  end

  describe "what B01a does not see" do
    it "keeps requests for batches out of the lists of invoices" do
      policy!
      request = submit[:request]

      expect(Approvals::Inbox.for(owner).map(&:request)).not_to include(request)
    end
  end
end
