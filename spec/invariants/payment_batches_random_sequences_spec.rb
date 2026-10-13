require "rails_helper"

# B01b: after any sequence of operations - invoices posted, batches composed, put to approval, decided by the right and the wrong people, exported (with and without
# a recent second factor), said to be loaded in the bank, cancelled and the cancellation completed - the guarantees of the payment batches hold.
# The seed of a failing sequence is in the message: replay it.
#
#  I15. Σ payments = total of the batch; the file kept says that total and that number; its bytes are the ones whose SHA-256 was kept, forever.
#  I16. An invoice is in at most one active batch, `active` follows the state of the batch and of the payment, and no invoice is paid more than it is owed.
#  D.   Nobody authorized a batch they prepared (the entity did not allow it); nothing was exported without an approval of the batch as it was.
#  E.   A batch that was cancelled holds nothing.
RSpec.describe "Invariant — payment batches hold after random sequences" do
  include_context "with approvable batch"

  seeds = (1..12).to_a
  operations = 60
  ibans = %w[BE68539007547034 BE71096123456769 BE62510007547061]

  let(:suppliers) do
    ibans.each_with_index.map do |iban, i|
      create(:partner, :supplier, name: "Supplier #{i}", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: iban, created_by: owner, first_seen_at: 90.days.ago) }
    end
  end
  let(:people) { [ preparer, authorizer, owner, create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } ] }

  before do
    Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin])
    people
  end

  def operation(rng, state)
    case rng.rand(20)
    when 0..2 then state[:invoices] << posted(partner: suppliers.sample(random: rng), unit_price: [ 100, 400, 900, 1500 ].sample(random: rng))
    when 3..6 then compose(rng, state)
    when 7..9 then submit(rng)
    when 10..12 then decide(rng)
    when 13..14 then export(rng, state)
    when 15 then confirm_submission(rng)
    when 16 then cancel(rng) if rng.rand(3).zero?
    else confirm_cancellation(rng)
    end
  end

  def confirm_submission(rng)
    batch = any(Payments::Batch.exported, rng) or return
    Payments::ConfirmSubmission.call(batch: batch, user: people.sample(random: rng))
  end

  def confirm_cancellation(rng)
    batch = any(Payments::Batch.cancel_requested, rng) or return
    Payments::ConfirmCancellation.call(batch: batch, user: people.sample(random: rng))
  end

  def any(scope, rng) = scope.to_a.sample(random: rng)

  def compose(rng, state)
    chosen = state[:invoices].sample(rng.rand(1..3), random: rng)
    return if chosen.empty?

    result = Payments::ComposeBatch.call(bank_account: bank, execution_date: execution, selections: chosen.map { |i| { invoice_id: i.id } }, user: preparer)
    result[:batch].update!(bank_profile: profile) if result.success?
  end

  def submit(rng)
    batch = any(Payments::Batch.draft, rng) or return
    Payments::SubmitBatch.call(batch: batch, user: people.sample(random: rng))
  end

  def decide(rng)
    request = any(Approvals::Request.pending.for_batches, rng) or return
    Approvals::Decide.call(request: request, user: people.sample(random: rng), decision: %i[approved approved approved rejected].sample(random: rng), comment: "reason",
                           content_fingerprint: (rng.rand(6).zero? ? "0" * 64 : request.content_fingerprint))
  end

  def export(rng, state)
    batch = any(Payments::Batch.approved, rng) or return
    item = batch.items.first
    kept = item.remittance
    item.update_columns(remittance: "changed behind the back") if rng.rand(6).zero? # a change the pre-flight does not see, only the fingerprint of the approval
    result = Payments::ExportBatch.call(batch: batch, user: people.sample(random: rng), recent_second_factor: rng.rand(4) > 0)
    state[:files][batch.id] = batch.reload.file_sha256 if result.success?
    item.update_columns(remittance: kept) unless result.success? # put right what the test changed, so that the sequence goes on
  end

  def cancel(rng)
    batch = any(Payments::Batch.where.not(status: %i[cancelled debited]), rng) or return
    Payments::CancelBatch.call(batch: batch, user: people.sample(random: rng), reason: [ "wrong date", "", "duplicate" ].sample(random: rng))
  end

  def check!(state, seed, step)
    where = "seed #{seed}, after operation #{step}"
    Payments::Batch.includes(items: :item_invoices).find_each do |batch|
      included = batch.items.select(&:included?)
      expect(batch.total).to eq(included.sum(&:amount)), "I15 total, #{where}"
      expect(batch.payments_count).to eq(included.size), "I15 count, #{where}"
      included.each { |item| expect(item.amount).to eq(item.item_invoices.sum(&:amount)), "I15 payment, #{where}" }
      check_file!(batch, state, where)
      check_activity!(batch, where)
      expect(authorizers_of(batch)).not_to include(batch.prepared_by_id), "D preparer authorized, #{where}" if batch.prepared_by_id
    end
    check_invoices!(where)
  end

  def check_file!(batch, state, where)
    return unless batch.file_sha256

    expect(Digest::SHA256.hexdigest(batch.document.file.download)).to eq(batch.file_sha256), "I15 file bytes, #{where}"
    expect(state[:files].fetch(batch.id, batch.file_sha256)).to eq(batch.file_sha256), "I15 file changed, #{where}"
    xml = Nokogiri::XML(batch.document.file.download).tap(&:remove_namespaces!)
    expect(BigDecimal(xml.at("GrpHdr/CtrlSum").text)).to eq(batch.total), "I15 control sum, #{where}"
    expect(xml.at("GrpHdr/NbOfTxs").text.to_i).to eq(batch.payments_count), "I15 number of payments, #{where}"
    expect(batch.approval_request).to be_approved, "D exported without an approval, #{where}"
    expect(batch.approval_request.content_fingerprint).to eq(Approvals::ContentFingerprint.call(batch)), "D exported on another content, #{where}"
  end

  def check_activity!(batch, where)
    batch.items.each do |item|
      expected = batch.active? && item.included?
      expect(item.item_invoices.map(&:active)).to all(eq(expected)), "I16 active flag (#{batch.status}), #{where}"
    end
    expect(batch.items.flat_map(&:item_invoices).any?(&:active)).to be(false), "E cancelled batch holds, #{where}" if batch.cancelled?
  end

  def authorizers_of(batch)
    return [] unless batch.approval_request

    batch.approval_request.decisions.approved.map { |d| d.on_behalf_of_id || d.approver_id }
  end

  def check_invoices!(where)
    active = Payments::ItemInvoice.where(active: true)
    expect(active.group(:invoice_id).having("COUNT(*) > 1").count).to be_empty, "I16 two active batches, #{where}"
    active.group(:invoice_id).sum(:amount).each do |invoice_id, amount|
      expect(amount).to be <= Accounting::Invoice.find(invoice_id).total_incl_vat, "I16 paid more than owed, #{where}"
    end
  end

  seeds.each do |seed|
    it "holds for seed #{seed}" do
      rng = Random.new(seed)
      suppliers
      state = { invoices: [], files: {} }
      operations.times do |step|
        operation(rng, state)
        check!(state, seed, step)
      end
    end
  end
end
