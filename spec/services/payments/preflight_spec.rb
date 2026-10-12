require "rails_helper"

# B01b §5 "Contrôles préalables": a deterministic report. Errors block; warnings need a reason, written by a person; some things are only told.
RSpec.describe Payments::Preflight do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:monday) { Time.zone.local(2026, 10, 12, 10, 0) }
  let(:execution) { Date.new(2026, 10, 14) } # a Wednesday
  let(:bank) { create(:bank_account, currency: "EUR") }
  let(:preparer) { create(:user, full_name: "Anna Assistant").tap { |u| create(:user_entity, :assistant, user: u, entity: entity) } }
  let(:accountant) { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:owner) { create(:user, full_name: "Olga Owner").tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let(:supplier) { create(:partner, :supplier, name: "Acme Ltd", iban: nil) }
  let!(:account) { create(:partner_bank_account, :verified, partner: supplier, iban: "BE68539007547034", created_by: owner, first_seen_at: 90.days.ago) }

  around { |example| travel_to(monday) { example.run } }

  before { fund(100_000) }

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

    result[:batch]
  end

  def codes(report, kind) = report.public_send(kind).map(&:code)

  let(:invoice) { posted }
  let(:batch) { batch_of(invoice) }

  describe "a batch with nothing wrong" do
    it "has no error and no warning, is ready, and the report is kept on the batch" do
      report = described_class.call(batch)

      expect(report.errors).to be_empty
      expect(report.warnings).to be_empty
      expect(report).to be_ready
      expect(batch.reload.preflight_report).to include("errors" => [], "warnings" => [], "generated_at" => a_string_matching(/2026-10-12/))
    end

    it "gives the same report twice (apart from its time), and writes nothing else" do
      first = described_class.call(batch).to_h.except("generated_at")
      second = described_class.call(batch).to_h.except("generated_at")

      expect(second).to eq(first)
    end
  end

  describe "errors, which block" do
    it "the account paid is no longer usable (blocked since the batch was made)" do
      batch
      account.update!(status: :blocked)

      report = described_class.call(batch)

      expect(codes(report, :errors)).to include(:account_not_usable)
      expect(report).not_to be_ready
      expect(report.errors.first.message).to include("Acme Ltd")
    end

    it "the supplier has another verified account now, so the one in the batch is out of date" do
      batch
      newer = create(:partner_bank_account, :verified, partner: supplier, iban: "FR1420041010050500013M02606", created_by: owner, verified_at: Time.current + 1.minute)
      account.update!(status: :superseded)

      report = described_class.call(batch)

      expect(codes(report, :errors)).to include(:account_changed)
      expect(newer).to be_persisted
    end

    it "the IBAN an invoice carries is not the account paid" do
      batch
      invoice.update_columns(iban: "FR1420041010050500013M02606")

      expect(codes(described_class.call(batch), :errors)).to include(:iban_differs)
    end

    it "an invoice is not approved (any more), or its approval is no longer of its content" do
      batch
      invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:to_approve])
      expect(codes(described_class.call(batch), :errors)).to include(:not_approved)

      invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:approved])
      policy = Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1)
      policy.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
      Approvals::Request.create!(subject: invoice, policy: policy, policy_version: 1, status: :approved, content_fingerprint: "0" * 64)
      expect(codes(described_class.call(batch), :errors)).to include(:approval_stale)

      Approvals::Request.where(subject: invoice).update_all(content_fingerprint: Approvals::ContentFingerprint.call(invoice))
      expect(codes(described_class.call(batch), :errors)).not_to include(:approval_stale)
    end

    it "an invoice is held, or has been paid meanwhile (its rest is below what the batch pays)" do
      batch
      Payments::Hold.create!(invoice: invoice, reason: "Goods not received", created_by: owner)
      expect(codes(described_class.call(batch), :errors)).to include(:on_hold)

      Payments::Hold.update_all(released_at: Time.current)
      line = invoice.journal_entry.lines.find_by(account: account_440)
      payment = create(:journal_entry, :draft, journal: create(:journal, :bank), fiscal_year: fiscal_year, entry_date: Date.current, reference: "PAYMENT-#{SecureRandom.hex(3)}")
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      debit = create(:journal_entry_line, journal_entry: payment, account: account_440, partner: supplier, debit: 300, credit: 0)
      create(:journal_entry_line, journal_entry: payment, account: account_550, debit: 0, credit: 300)
      Accounting::PostJournalEntry.call!(entry: payment)
      Accounting::LineAllocation.create!(debit_line: debit, credit_line: line, amount: 300, allocated_on: Date.current)

      report = described_class.call(batch)

      expect(codes(report, :errors)).to include(:rest_changed)
      expect(report.errors.find { |e| e.code == :rest_changed }.message).to include("910.00")
    end

    it "the execution date is in the past, a weekend, a TARGET holiday, or a day the bank closes" do
      { Date.new(2026, 10, 9) => :past, Date.new(2026, 10, 17) => :closed, Date.new(2026, 12, 25) => :closed }.each do |date, _|
        b = batch_of(posted, date: date)
        expect(codes(described_class.call(b), :errors)).to include(:execution_date), date.to_s
        b.update!(status: :cancelled)
      end
      profile = Payments::BankProfile.create!(name: "Crelan", format_version: "pain.001.001.03", options: { "closed_days" => [ "2026-10-14" ] })
      b = batch_of(posted)
      b.update!(bank_profile: profile)

      expect(codes(described_class.call(b), :errors)).to include(:execution_date)
    end

    it "a structured communication that does not check (modulo 97), while a free text of twelve digits is only text" do
      bad = posted(payment_reference: "+++090/9337/55494+++")
      expect(codes(described_class.call(batch_of(bad)), :errors)).to include(:structured_communication)

      free = posted(payment_reference: "PO 123456789012")
      expect(codes(described_class.call(batch_of(free)), :errors)).not_to include(:structured_communication)
      good = posted(payment_reference: "+++090/9337/55493+++")
      expect(codes(described_class.call(batch_of(good)), :errors)).not_to include(:structured_communication)
    end

    it "the limits of the bank profile: payments in a file, total of a batch, total to a supplier" do
      other = create(:partner, :supplier, name: "Beta SA", iban: nil)
      create(:partner_bank_account, :verified, partner: other, iban: "FR1420041010050500013M02606", created_by: owner)
      b = batch_of(posted, posted(partner: other))
      profile = Payments::BankProfile.create!(name: "Crelan", format_version: "pain.001.001.03", max_payments: 1, max_batch_total: 2000, max_supplier_total: 1000)
      b.update!(bank_profile: profile)

      report = described_class.call(b)

      expect(codes(report, :errors)).to include(:limit_payments, :limit_batch_total, :limit_supplier_total)
    end

    it "the totals of the batch, of its payments and of what they pay do not agree (I15)" do
      batch
      batch.items.first.update_columns(amount: 1.00)

      expect(codes(described_class.call(batch), :errors)).to include(:totals)
    end
  end

  describe "warnings, which need a reason" do
    it "a probable duplicate: the same supplier, amount and remittance in a batch of the last 90 days that is not cancelled" do
      earlier = batch_of(posted(unit_price: 1000))
      earlier.update!(status: :exported)
      earlier.items.update_all(remittance: "Invoice X")
      current = batch_of(posted(unit_price: 1000))
      current.items.update_all(remittance: "Invoice X")

      expect(codes(described_class.call(current), :warnings)).to include(:probable_duplicate)

      earlier.update_columns(status: Payments::Batch.statuses[:cancelled])
      expect(codes(described_class.call(current), :warnings)).not_to include(:probable_duplicate)

      earlier.update_columns(status: Payments::Batch.statuses[:exported], created_at: 120.days.ago)
      expect(codes(described_class.call(current), :warnings)).not_to include(:probable_duplicate)
    end

    it "the balance of the account debited would fall under the threshold after the batch" do
      b = batch_of(posted(unit_price: 1000))
      Payments::BankProfile.create!(name: "p", format_version: "pain.001.001.03", balance_threshold: 99_000).tap { |p| b.update!(bank_profile: p) }

      report = described_class.call(b)

      expect(codes(report, :warnings)).to include(:low_balance)
      expect(report.warnings.find { |w| w.code == :low_balance }.message).to include("100000.00")
    end

    it "the balance is enough: nothing said" do
      b = batch_of(posted(unit_price: 1000))

      expect(codes(described_class.call(b), :warnings)).not_to include(:low_balance)
    end

    it "a payment of more than twice what the supplier's invoices usually are" do
      3.times { |n| posted(unit_price: 100, due: Date.current - 30 - n).tap { |i| i.update_columns(status: Accounting::Invoice.statuses[:paid]) } }
      big = batch_of(posted(unit_price: 1000))

      expect(codes(described_class.call(big), :warnings)).to include(:unusual_amount)
    end

    it "more than three accounts that are new or changed within the batch" do
      suppliers = Array.new(4) do |n|
        create(:partner, :supplier, name: "New #{n}", iban: nil).tap do |p|
          create(:partner_bank_account, :verified, partner: p, iban: [ "FR1420041010050500013M02606", "NL91ABNA0417164300", "DE89370400440532013000", "IT60X0542811101000000123456" ][n], created_by: owner, first_seen_at: 5.days.ago)
        end
      end
      many = batch_of(*suppliers.map { |s| posted(partner: s, unit_price: 100) })
      three = batch_of(*suppliers.first(3).map { |s| posted(partner: s, unit_price: 100) })

      expect(codes(described_class.call(many), :warnings)).to include(:many_new_accounts)
      expect(codes(described_class.call(three), :warnings)).not_to include(:many_new_accounts)
    end
  end

  describe "information" do
    it "says what the SEPA character set changes in a name or a remittance" do
      supplier.update!(name: "Café Müller")
      account.update_columns(holder_name: "Café Müller")
      b = batch_of(posted)

      report = described_class.call(b)

      expect(codes(report, :infos)).to include(:transliterated)
      expect(report.infos.first.message).to include("Café Müller").and include("Cafe Muller")
      expect(report).to be_ready # information never blocks
    end
  end

  describe "acknowledging a warning" do
    let(:big) do
      3.times { |n| posted(unit_price: 100, due: Date.current - 30 - n).tap { |i| i.update_columns(status: Accounting::Invoice.statuses[:paid]) } }
      batch_of(posted(unit_price: 1000))
    end

    def acknowledge(b, code: :unusual_amount, reason: "Agreed with the supplier on the phone", user: accountant)
      key = described_class.call(b).warnings.find { |w| w.code == code }.key
      Payments::AcknowledgeWarning.call(batch: b, key: key, reason: reason, user: user)
    end

    it "is needed before the batch is ready, and takes a reason and a person" do
      expect(described_class.call(big)).not_to be_ready

      expect(acknowledge(big, reason: "")).to be_failure
      result = acknowledge(big)

      expect(result).to be_success
      expect(described_class.call(big)).to be_ready
      ack = big.reload.preflight_report.dig("acknowledgements").values.sole
      expect(ack).to include("reason" => "Agreed with the supplier on the phone", "user" => "Alice Accountant")
      expect(Accounting::AuditLog.where(action: "payment_warning_acknowledged").sole.payload).to include("code" => "unusual_amount", "reason" => "Agreed with the supplier on the phone")
    end

    it "holds for the same finding on a later run, not for a new one" do
      acknowledge(big)
      big.items.first.update_columns(remittance: "Another text") # nothing that changes the finding

      expect(described_class.call(big)).to be_ready

      other = create(:partner, :supplier, name: "Beta SA", iban: nil)
      create(:partner_bank_account, :verified, partner: other, iban: "FR1420041010050500013M02606", created_by: owner)
      batch_two = batch_of(posted(partner: other, unit_price: 500))
      Payments::BankProfile.create!(name: "p", format_version: "pain.001.001.03", balance_threshold: 10_000_000).tap { |p| batch_two.update!(bank_profile: p) }
      expect(described_class.call(batch_two)).not_to be_ready
    end

    it "is not for an error: a blocking problem cannot be waived" do
      batch
      account.update!(status: :blocked)
      key = described_class.call(batch).errors.first.key

      result = Payments::AcknowledgeWarning.call(batch: batch, key: key, reason: "I know", user: accountant)

      expect(result).to be_failure
      expect(described_class.call(batch)).not_to be_ready
    end

    it "is for someone who may prepare or approve a batch, not a reader" do
      reader = create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) }
      described_class.call(big)

      expect(acknowledge(big, user: reader)).to be_failure
    end
  end
end
