require "rails_helper"

# B02b, firm side: the mail kept in quarantine (a stranger, an authentication not vouched for), the review, and the addresses the firm allows besides the people of the portal.
RSpec.describe "Mail quarantine (firm side)", type: :request do
  include_context "with entity"
  include DocumentFiles

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }

  def quarantine(subject: "Invoices", sender: "stranger@elsewhere.example", reason: "sender_not_allowed")
    mail = Mail.new(from: sender, to: entity.documents_email, subject: subject, body: "See attached.")
    mail.add_file(filename: "late.pdf", content: sample_pdf("late #{subject}"))
    Accounting::MailQuarantine.create!(sender: sender, subject: subject, message_id: mail.message_id.to_s, reason: reason, raw: mail.encoded, attachment_count: 1)
  end

  before { sign_in accountant }

  it "lists what waits, with who sent it and why it is held, and never the content" do
    quarantine(subject: "March invoices")

    get accounting_mail_quarantines_path

    expect(response.body).to include("stranger@elsewhere.example", "March invoices", "sender is not allowed")
    expect(response.body).not_to include("See attached")
  end

  it "releases a mail" do
    item = quarantine

    post release_accounting_mail_quarantine_path(item)

    expect(response).to redirect_to(accounting_mail_quarantines_path)
    expect(item.reload.status).to eq("released")
    expect(Accounting::Document.pluck(:name)).to eq([ "late.pdf" ])
  end

  it "discards a mail" do
    item = quarantine
    post discard_accounting_mail_quarantine_path(item)
    expect(item.reload.status).to eq("discarded")
    expect(Accounting::Document.count).to eq(0)
  end

  it "keeps what was reviewed out of the waiting list" do
    item = quarantine(subject: "Old news")
    PortalAdmin::ReviewMail.discard(item, by: accountant)

    get accounting_mail_quarantines_path

    expect(response.body).not_to include("Old news")
  end

  it "does not show the mail of another company" do
    foreign = ActsAsTenant.with_tenant(create(:entity)) { quarantine(subject: "Foreign mail") }
    get accounting_mail_quarantines_path
    expect(response.body).not_to include("Foreign mail")
    expect { post release_accounting_mail_quarantine_path(foreign) }.not_to change(Accounting::Document, :count)
  end

  it "keeps the list of the addresses allowed besides the people of the portal, in lower case, valid ones only" do
    patch settings_accounting_mail_quarantines_path, params: { allowed_senders: "Bookkeeper@Partner.example\nnot an address\n\n  boss@client.example " }

    expect(entity.reload.documents_allowed_senders).to eq(%w[bookkeeper@partner.example boss@client.example])
    expect(Accounting::AuditLog.where(action: "documents_allowed_senders_changed").count).to eq(1)
  end

  it "is for those who manage the portal" do
    sign_in reader
    item = quarantine
    post release_accounting_mail_quarantine_path(item)
    expect(item.reload.status).to eq("pending")
  end

  it "is closed while the feature is off" do
    entity.update!(features: { "b02b" => false })
    get accounting_mail_quarantines_path
    expect(response).to redirect_to(accounting_root_path)
  end
end
