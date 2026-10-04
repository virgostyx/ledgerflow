require "rails_helper"

# F06 step 4: the "Received invoices" screen, as a person uses it: a message waits, its cause is read, it is worked on again, then put aside.
RSpec.describe "Received Peppol invoices", type: :system, js: true do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  include_context "with_suspense_account"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:purchase_journal) { create(:journal, :purchase) }

  def take(xml, id) = Peppol::ReceiveMessage.call(event: Peppol::Event.new(kind: :received, message_id: id, receiver: "0208:0999999999", xml: xml))[:message]

  before do
    take(PeppolUbl.invoice(number: "SUP-DONE"), "AP-1")
    take(PeppolUbl.invoice(number: "SUP-WAIT", lines: [ [ 100, "K", 0 ] ]), "AP-2")
    login_as accountant, scope: :user
  end

  it "shows what waits and why, works on it again, and puts it aside with a reason" do
    visit accounting_peppol_messages_path

    expect(page).to have_content("SUP-DONE")
    expect(page).to have_content("Waiting for review")
    click_link "AP-2"

    expect(page).to have_content("This message waits")
    expect(page).to have_content("not mapped")
    expect(page).to have_content("The XML as received")

    click_button "Work on it again"
    expect(page).to have_content("Still waiting")

    fill_in "reason", with: "Not addressed to us"
    click_button "Put aside"

    expect(page).to have_content("Message put aside")
    expect(Accounting::PeppolMessage.find_by(message_id: "AP-2")).to be_dismissed
  end

  it "drafts the message once its category is mapped, from the list, in one click" do
    Accounting::VatCategoryMapping.create!(category: "K", vat_treatment: :intracom_goods, vat_rate: 21)
    visit accounting_peppol_messages_path(status: "needs_review")

    check "message_ids_#{Accounting::PeppolMessage.find_by(message_id: 'AP-2').id}"
    click_button "Work on the ticked messages again"

    expect(page).to have_content("1 of 1 message(s) drafted")
    expect(Accounting::PeppolMessage.find_by(message_id: "AP-2")).to be_processed
  end
end
