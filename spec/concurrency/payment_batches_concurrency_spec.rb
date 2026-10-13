require "rails_helper"

# B01b: what must hold when two people (or two clicks) act on payments at the same moment: an invoice goes into one batch, a batch is approved once, the file is made once.
RSpec.describe "Payment batches under concurrency", :concurrency do
  include_context "with approvable batch"

  let(:second_authorizer) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }

  def compose(invoice, user = preparer)
    -> { Payments::ComposeBatch.call(bank_account: Accounting::BankAccount.find(bank.id), execution_date: execution, selections: [ { invoice_id: invoice.id } ], user: User.find(user.id)) }
  end

  it "puts an invoice in one batch only when two people compose at the same moment" do
    invoice = posted
    other = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) }

    results = concurrently(compose(invoice), compose(invoice, other), entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(Payments::ItemInvoice.where(invoice_id: invoice.id, active: true).count).to eq(1)
    expect(Payments::Batch.count).to eq(1)
  end

  it "lets many people compose at the same moment, each with their own invoice, with distinct references" do
    invoices = Array.new(4) { posted(unit_price: 100) }

    results = concurrently(*invoices.map { |i| compose(i) }, entity: entity)

    expect(results).to all(be_success)
    expect(Payments::Batch.pluck(:reference).uniq.size).to eq(4)
  end

  it "approves a batch once when two approvers click at the same moment" do
    batch = approved_pending_batch
    request = batch.approval_request
    decide = ->(who) { -> { Approvals::Decide.call(request: Approvals::Request.find(request.id), user: User.find(who.id), decision: :approved, content_fingerprint: request.content_fingerprint) } }

    results = concurrently(decide.call(authorizer), decide.call(second_authorizer), entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(request.reload.decisions.approved.count).to eq(1)
    expect(batch.reload).to be_approved
  end

  it "makes the file once when two exports run at the same moment" do
    batch = approved_batch
    export = -> { Payments::ExportBatch.call(batch: Payments::Batch.find(batch.id), user: User.find(authorizer.id), recent_second_factor: true) }

    results = concurrently(export, export, entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(Accounting::Document.where(origin: :payment_file).count).to eq(1)
    expect(Accounting::AuditLog.where(action: "payment_batch_exported", auditable_id: batch.id).count).to eq(1)
  end

  it "says once that the file was loaded in the bank when two people click at the same moment" do
    batch = approved_batch
    Payments::ExportBatch.call(batch: batch, user: authorizer, recent_second_factor: true)
    confirm = ->(who) { -> { Payments::ConfirmSubmission.call(batch: Payments::Batch.find(batch.id), user: User.find(who.id)) } }

    results = concurrently(confirm.call(authorizer), confirm.call(second_authorizer), entity: entity)

    expect(results.count(&:success?)).to eq(1)
    expect(Accounting::AuditLog.where(action: "payment_batch_submitted", auditable_id: batch.id).count).to eq(1)
  end

  def approved_pending_batch
    batch = batch_of(posted)
    Approvals::Policy.create!(name: "batches", subject: :payment_batch, priority: 1).steps.create!(position: 1, mode: :any_of, approver_roles: %w[accountant admin])
    Payments::SubmitBatch.call(batch: batch, user: preparer)
    batch.reload
  end
end
