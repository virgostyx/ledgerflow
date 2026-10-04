require "rails_helper"

# F06 step 4: what a person does with a message that waits. Never deletes, never posts.
RSpec.describe Peppol::MessageActions do
  include_context "with_open_fiscal_year"
  include_context "with_suspense_account"

  let(:user) { create(:user, role: :accountant) }

  def take(xml) = Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: SecureRandom.hex(4), receiver: "0208:0999999999", xml: xml))[:message]

  let!(:waiting) { take(PeppolUbl.invoice(lines: [ [ 100, "K", 0 ] ])) } # category K, not mapped

  it "works on a message again, and drafts it once the category is mapped" do
    Accounting::VatCategoryMapping.create!(category: "K", vat_treatment: :intracom_goods, vat_rate: 21)

    result = described_class.reprocess(message: waiting, user: user)

    expect(result).to be_success
    expect(waiting.reload).to have_attributes(status: "processed", problems: [])
    expect(waiting.invoice).to have_attributes(vat_treatment: "intracom_goods", status: "draft")
  end

  it "leaves the message waiting, with its reasons, when the cause is still there" do
    described_class.reprocess(message: waiting, user: user)

    expect(waiting.reload).to be_needs_review
    expect(waiting.problems.join).to include("not mapped")
  end

  it "does not work again on what is not waiting, nor put aside what is drafted" do
    done = take(PeppolUbl.invoice)

    expect(described_class.reprocess(message: done, user: user)).to be_failure
    expect(described_class.dismiss(message: done, user: user, reason: "x")).to be_failure
    expect(described_class.assign_supplier(message: done, partner: create(:partner), user: user)).to be_failure
  end

  it "puts a message aside with a reason, keeps it whole, and records who and why" do
    result = described_class.dismiss(message: waiting, user: user, reason: "  Sent to us by mistake  ")

    expect(result).to be_success
    expect(waiting.reload).to have_attributes(status: "dismissed")
    expect(waiting.xml).to be_present
    log = Accounting::AuditLog.where(auditable_type: "Accounting::PeppolMessage", auditable_id: waiting.id, action: "peppol_message_dismissed").sole
    expect([ log.user_id, log.reason ]).to eq([ user.id, "Sent to us by mistake" ])
  end

  it "needs a reason to put a message aside" do
    expect(described_class.dismiss(message: waiting, user: user, reason: nil)).to be_failure
    expect(waiting.reload).to be_needs_review
  end

  it "never posts what it drafts" do
    Accounting::VatCategoryMapping.create!(category: "K", vat_treatment: :intracom_goods, vat_rate: 21)
    described_class.reprocess(message: waiting, user: user)

    expect(waiting.reload.invoice).to be_draft
  end
end
