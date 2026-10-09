require "rails_helper"

# B01a §4 "Fonctionnement" 1: an invoice is put to approval, or recorded as needing none.
RSpec.describe Approvals::Submit do
  include_context "with entity"

  let(:author)      { create(:user) }
  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:invoice) do
    create(:invoice, :supplier, created_by: author, fiscal_year: fiscal_year).tap do |i|
      create(:invoice_line, invoice: i, account: create(:account), unit_price: "1000.00")
    end
  end

  def audit(action) = Accounting::AuditLog.for_record(invoice).for_action(action)

  def policy!(**conditions)
    Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1, conditions: conditions).tap do |p|
      p.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
    end
  end

  it "records that no approval is needed when no policy applies, and says so in the audit" do
    result = described_class.call(invoice: invoice, user: author)

    expect(result).to be_success
    expect(result[:request]).to be_nil
    expect(invoice.reload).to be_payment_not_required
    expect(audit("approval_not_required").count).to eq(1)
  end

  it "opens a request on the content, under the version of the policy, and waits for approval" do
    policy = policy!
    result = described_class.call(invoice: invoice, user: author)
    request = result[:request]

    expect(request).to be_pending
    expect(request.policy).to eq(policy)
    expect(request.policy_version).to eq(policy.version)
    expect(request.content_fingerprint).to eq(Approvals::ContentFingerprint.call(invoice))
    expect(request.submitted_by).to eq(author)
    expect(request.step_started_at).to be_present
    expect(request.current_step).to eq(1)
    expect(invoice.reload).to be_payment_to_approve
    expect(audit("approval_submitted").count).to eq(1)
  end

  it "does nothing the second time on the same content" do
    policy!
    first = described_class.call(invoice: invoice, user: author)[:request]

    expect { described_class.call(invoice: invoice, user: author) }.not_to change(Approvals::Request, :count)
    expect(described_class.call(invoice: invoice, user: author)[:request]).to eq(first)
    expect(audit("approval_submitted").count).to eq(1)
  end

  it "opens a new request after the earlier one asked for changes" do
    policy!
    first = described_class.call(invoice: invoice, user: author)[:request]
    first.update!(status: :changes_requested)

    second = described_class.call(invoice: invoice, user: author)[:request]

    expect(second).not_to eq(first)
    expect(second).to be_pending
  end

  it "keeps the version of a policy edited meanwhile" do
    policy = policy!
    request = described_class.call(invoice: invoice, user: author)[:request]
    policy.update!(version: 2)

    expect(request.reload.policy_version).to eq(1)
  end

  it "refuses a customer invoice" do
    customer = create(:invoice, :customer, fiscal_year: fiscal_year)

    expect(described_class.call(invoice: customer, user: author)).to be_failure
  end

  it "refuses an invoice that is cancelled or already paid" do
    invoice.update_columns(status: Accounting::Invoice.statuses[:cancelled])

    expect(described_class.call(invoice: invoice, user: author)).to be_failure
  end

  it "refuses when the feature is off for the entity" do
    entity.update!(features: entity.features.merge("b01a" => false))

    expect(described_class.call(invoice: invoice, user: author)).to be_failure
  end
end
