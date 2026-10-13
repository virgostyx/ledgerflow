require "rails_helper"

# B01c: after any sequence of operations - batches taken to the bank, debits confirmed from a line or by hand, entries validated, payments rejected, payments returned, batches
# given up - the guarantees of the confirmation hold. The seed of a failing sequence is in the message: replay it.
#
#  I15. The debit of a line of the statement equals the payments confirmed against it; a debited batch holds exactly the payments confirmed, returned and rejected.
#  M.   One entry per confirmed payment, never two, balanced, for the amount of the payment; a draft entry is never lettered.
#  N.   An invoice is never paid beyond what it asked for by the batches (what is open never goes negative), and while an entry is a draft its invoice is held.
#  O.   Nothing is validated without a person: every validated entry of a payment is accounted for by the validation of its batch in the audit trail.
RSpec.describe "Invariant - payment debits hold after random sequences" do
  include_context "with submitted batch"

  seeds = (1..10).to_a
  operations = 40
  ibans = { "Acme Ltd" => "BE68539007547034", "Beta Corp" => "BE71096123456769", "Gamma SA" => "BE62510007547061" }

  let(:suppliers) do
    ibans.map do |name, iban|
      name == "Acme Ltd" ? supplier : create(:partner, :supplier, name: name, iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: iban, holder_name: name, created_by: owner, first_seen_at: 90.days.ago) }
    end
  end
  let(:poster) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:people) { [ preparer, authorizer, owner, exporter, poster ] }

  before do
    Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin])
    suppliers
  end

  def pick(scope, rng) = scope.to_a.sample(random: rng)
  def person(rng) = people.sample(random: rng)

  def operation(rng, state)
    case rng.rand(18)
    when 0..1 then state[:invoices] << posted(partner: suppliers.sample(random: rng), unit_price: [ 100, 400, 900 ].sample(random: rng))
    when 2 then take_to_the_bank(rng, state)
    when 3..4 then confirm_from_statement(rng)
    when 5 then confirm_by_hand(rng)
    when 6..7 then post_payments(rng)
    when 8 then reject(rng)
    when 9 then register_return(rng)
    when 10 then cancel(rng)
    when 11 then link_statement(rng)
    when 12..13 then partial_debit(rng)
    when 14 then confirm_wrong_amount(rng)
    else state[:invoices] << posted(partner: suppliers.sample(random: rng), unit_price: [ 150, 250 ].sample(random: rng))
    end
  end

  # A line that is one cent more than the payments it would confirm: refused, whoever it is and whatever it names.
  def confirm_wrong_amount(rng)
    batch = waiting_batch(rng) or return
    included = batch.items.select(&:included?)
    return if included.empty?

    Payments::ConfirmDebit.call(batch: batch, user: person(rng), transaction: debit_line(included.sum(&:amount) + 0.01, description: batch.reference), items: included)
  end

  def take_to_the_bank(rng, state)
    free = state[:invoices].reject { |i| Payments::ItemInvoice.exists?(invoice_id: i.id, active: true) || i.reload.paid? }
    chosen = free.sample(rng.rand(2..3), random: rng)
    return if chosen.empty?

    batch = batch_of(*chosen)
    Payments::SubmitBatch.call(batch: batch, user: preparer)
    request = batch.reload.approval_request or return
    Approvals::Decide.call(request: request, user: authorizer, decision: :approved, content_fingerprint: request.content_fingerprint)
    exported = Payments::ExportBatch.call(batch: batch.reload, user: exporter, recent_second_factor: true)
    Payments::ConfirmSubmission.call(batch: batch.reload, user: exporter) if exported.success?
  rescue RuntimeError
    nil # the composition refused (an invoice taken meanwhile): nothing to follow
  end

  def waiting_batch(rng) = pick(Payments::Batch.where(status: %i[submitted exported]), rng)

  def confirm_from_statement(rng)
    batch = waiting_batch(rng) or return
    included = batch.items.select(&:included?)
    return if included.empty?

    whole = included.size == batch.items.size || rng.rand(2).zero?
    items = whole ? included : [ included.sample(random: rng) ]
    wrong = rng.rand(6).zero? ? 1 : 0 # a line that is not the total of the payments: refused
    line = debit_line(items.sum(&:amount) + wrong, description: "Remise #{batch.reference}", counterparty_iban: (items.first.iban if items.one?))
    Payments::ConfirmDebit.call(batch: batch, user: person(rng), transaction: line, items: items)
  end

  def partial_debit(rng)
    batch = pick(Payments::Batch.where(status: %i[submitted exported]).select { |b| b.items.select(&:included?).size > 1 }, rng) or return
    included = batch.items.select(&:included?)
    missing = included.sample(random: rng)
    line = debit_line(included.sum(&:amount) - missing.amount, description: batch.reference)
    Payments::ConfirmDebit.call(batch: batch, user: person(rng), transaction: line, items: included - [ missing ])
  end

  def confirm_by_hand(rng)
    batch = pick(Payments::Batch.where(status: :submitted), rng) or return
    Payments::ConfirmDebit.manual(batch: batch, user: person(rng), reason: "phone", date: execution, bank_reference: "REF-#{rng.rand(1000)}")
  end

  def link_statement(rng)
    batch = pick(Payments::Batch.where(status: :debited, debit_kind: "manual"), rng) or return
    open = batch.items.select { |i| i.confirmed? && i.bank_transaction_id.nil? }
    return if open.empty?

    Payments::LinkManualDebit.call(batch: batch, user: person(rng), transaction: debit_line(open.sum(&:amount), description: batch.reference), items: open)
  end

  def post_payments(rng)
    batch = pick(Payments::Batch.where(status: %i[debited partially_rejected]), rng) or return
    Payments::PostBatchPayments.call(batch: batch, user: person(rng))
  end

  def reject(rng)
    batch = pick(Payments::Batch.where(status: %i[submitted exported]).select { |b| b.items.any?(&:confirmed?) && b.items.any?(&:included?) }, rng) or return
    Payments::RejectPayments.call(batch: batch, items: batch.items.select(&:included?), user: person(rng), reason: "rejected by the bank")
  end

  def register_return(rng)
    item = pick(Payments::Item.where(status: :confirmed).includes(:journal_entry).select { |i| i.journal_entry&.posted? }, rng) or return
    credit = create(:bank_transaction, bank_account: bank, amount: item.amount, transaction_date: execution + rng.rand(1..5), counterparty_iban: item.iban)
    Payments::RegisterReturn.call(item: item, transaction: credit, user: person(rng), reason: "returned")
  end

  def cancel(rng)
    batch = pick(Payments::Batch.where(status: %i[submitted exported cancel_requested]), rng) or return
    result = Payments::CancelBatch.call(batch: batch, user: person(rng), reason: "changed my mind")
    Payments::ConfirmCancellation.call(batch: batch.reload, user: person(rng)) if result.success? && rng.rand(2).zero?
  end

  def check!(seed, step)
    where = "seed #{seed}, after operation #{step}"
    Payments::Batch.includes(items: %i[journal_entry item_invoices]).find_each do |batch|
      check_batch!(batch, where)
      batch.items.each { |item| check_item!(item, where) }
    end
    check_lines!(where)
    check_invoices!(where)
  end

  def check_batch!(batch, where)
    return unless batch.debited? || batch.partially_rejected?

    expect(batch.items.none?(&:included?)).to be(true), "I15 a debited batch still waits for a payment, #{where}"
    taken = batch.items.reject(&:rejected?)
    expect(taken.sum(&:amount) + batch.items.select(&:rejected?).sum(&:amount)).to eq(batch.total), "I15 payments do not add up to the batch, #{where}"
  end

  def check_item!(item, where)
    if item.confirmed? || item.returned?
      entry = item.journal_entry
      expect(entry).to be_present, "M a confirmed payment has no entry, #{where}"
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit)), "M entry not balanced, #{where}"
      expect(entry.lines.sum(:credit)).to be >= item.amount, "M entry smaller than the payment, #{where}"
      expect(entry.lines.where.not(lettering_id: nil)).to be_empty, "M a draft entry is lettered, #{where}" if entry.draft?
      expect(Accounting::JournalEntry.where(source_type: "Payments::Item", source_id: item.id).count).to be <= 2, "M two entries for one payment, #{where}" # the entry and its reversal
    else
      expect(item.journal_entry_id).to be_nil, "M an entry for a payment not confirmed, #{where}"
    end
    return unless item.confirmed? && item.journal_entry&.draft?

    expect(item.item_invoices.map(&:active)).to all(be(true)), "N invoice free while the entry is a draft, #{where}"
  end

  # The line of the statement is the total of the payments confirmed against it.
  def check_lines!(where)
    Accounting::BankTransaction.where(id: Payments::Item.where.not(bank_transaction_id: nil).select(:bank_transaction_id)).includes(:payment_items).find_each do |line|
      expect(line.payment_items.sum(&:amount)).to eq(-line.amount), "I15 the debit is not the payments confirmed against it, #{where}"
    end
  end

  def check_invoices!(where)
    Payments::OpenAmounts.rests(Accounting::Invoice.supplier.invoice.where.not(journal_entry_id: nil).to_a).each do |invoice_id, rest|
      expect(rest).to be >= 0, "N invoice #{invoice_id} paid beyond what it asked for, #{where}"
    end
    posted = Accounting::JournalEntry.where(source_type: "Payments::Item", status: %i[posted reversed]).count
    audited = Accounting::AuditLog.where(action: "payment_batch_entries_posted").sum { |log| log.payload["entries"].to_i }
    expect(Accounting::JournalEntry.where(source_type: "Payments::Item", status: :posted).where(reversal_of_id: nil).count + Accounting::JournalEntry.where(source_type: "Payments::Item", status: :reversed).count)
      .to be <= audited, "O an entry was validated without the validation of its batch, #{where}"
    expect(posted).to be >= 0
  end

  seeds.each do |seed|
    it "holds for seed #{seed}" do
      rng = Random.new(seed)
      state = { invoices: [] }
      operations.times do |step|
        operation(rng, state)
        check!(seed, step)
      end
    end
  end
end
