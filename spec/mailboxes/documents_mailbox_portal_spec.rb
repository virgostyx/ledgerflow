require "rails_helper"

# B02b, "Adresse e-mail dédiée": with the portal's document upload on, the address takes mail only from the people of the company's portal and from addresses the firm lists, and only when the
# receiving server vouched for SPF and DKIM; the rest goes to quarantine for a person to look at. The auto-reply gives a count and nothing of the content.
RSpec.describe DocumentsMailbox, "with the client portal", type: :mailbox do
  include_context "with entity"
  include DocumentFiles

  let(:person) { create(:portal_user, email: "jane@client.example") }
  let(:authserv) { "mx.ledgerflow.example" }
  let(:passing) { "#{authserv}; spf=pass smtp.mailfrom=client.example; dkim=pass header.d=client.example" }

  around do |example|
    previous = Rails.configuration.x.mail_authserv_id
    Rails.configuration.x.mail_authserv_id = authserv
    example.run
  ensure
    Rails.configuration.x.mail_authserv_id = previous
  end

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: "collaborator", capabilities: %w[documents.upload])
    ActionMailer::Base.deliveries.clear
  end

  def receive(from: person.email, authentication: passing, headers: {}, files: [ [ "invoice.pdf", sample_pdf("one") ] ])
    receive_inbound_email_from_mail(to: entity.documents_email, from: from, subject: "Invoices", body: "See attached.") do |mail|
      mail.header["Authentication-Results"] = authentication if authentication
      headers.each { |name, value| mail.header[name] = value }
      files.each { |name, content| mail.add_file(filename: name, content: content) }
    end
  end

  def documents = Accounting::Document.order(:id)
  def quarantined = Accounting::MailQuarantine.order(:id)

  it "takes in the mail of a person of the portal that passes SPF and DKIM" do
    receive

    expect(documents.pluck(:name)).to eq([ "invoice.pdf" ])
    expect(quarantined).to be_empty
  end

  it "takes in the mail of an address the firm listed" do
    entity.update!(documents_allowed_senders: [ "bookkeeper@partner.example" ])

    receive(from: "Bookkeeper@Partner.example")

    expect(documents.count).to eq(1)
  end

  it "puts the mail of a stranger in quarantine, unread, and creates no document" do
    receive(from: "stranger@elsewhere.example")

    expect(documents).to be_empty
    expect(quarantined.sole).to have_attributes(sender: "stranger@elsewhere.example", reason: "sender_not_allowed", status: "pending", attachment_count: 1)
    expect(ActionMailer::Base.deliveries).to be_empty # no answer to someone who is not known
  end

  it "does not take the mail of a person whose access is revoked" do
    person.grants.update_all(revoked_at: Time.current)
    receive
    expect(documents).to be_empty
    expect(quarantined.sole.reason).to eq("sender_not_allowed")
  end

  it "puts in quarantine a mail the server did not vouch for: SPF failing, DKIM missing, or no result at all" do
    receive(authentication: "#{authserv}; spf=fail smtp.mailfrom=client.example; dkim=pass header.d=client.example")
    receive(authentication: "#{authserv}; spf=pass smtp.mailfrom=client.example; dkim=none")
    receive(authentication: nil)

    expect(documents).to be_empty
    expect(quarantined.pluck(:reason)).to eq(%w[authentication_failed] * 3)
  end

  it "trusts only the results written by its own server, not those a sender wrote himself" do
    receive(authentication: "evil.example; spf=pass; dkim=pass")
    expect(documents).to be_empty
    expect(quarantined.sole.reason).to eq("authentication_failed")
  end

  it "trusts nothing when the server's name is not configured" do
    Rails.configuration.x.mail_authserv_id = nil
    receive
    expect(quarantined.sole.reason).to eq("authentication_failed")
  end

  it "answers with the number of documents received and nothing of what they are" do
    receive(files: [ [ "secret-invoice.pdf", sample_pdf("a") ], [ "other.pdf", sample_pdf("b") ] ])

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ person.email ])
    expect(mail.body.to_s).to include("2 documents")
    expect(mail.body.to_s).not_to include("secret-invoice")
    expect(mail.header["Auto-Submitted"].to_s).to eq("auto-replied")
  end

  it "does not answer an automatic message, so that two machines never talk to each other" do
    receive(headers: { "Auto-Submitted" => "auto-generated" })
    receive(headers: { "Precedence" => "bulk" }, files: [ [ "x.pdf", sample_pdf("x") ] ])

    expect(documents.count).to eq(2)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "does nothing when the portal's document upload is off for the company: the F03 behaviour stays" do
    entity.update!(features: { "b02b" => false })
    receive(from: "stranger@elsewhere.example", authentication: nil)
    expect(documents.count).to eq(1)
  end

  describe "the review" do
    let(:reviewer) { create(:user) }

    def quarantine_one
      receive(from: "stranger@elsewhere.example", files: [ [ "late.pdf", sample_pdf("late") ] ])
      quarantined.sole
    end

    it "releases a mail: its attachments go through the usual upload, and the mail is marked" do
      item = quarantine_one

      result = PortalAdmin::ReviewMail.release(item, by: reviewer)

      expect(result).to be_success
      expect(documents.pluck(:name)).to eq([ "late.pdf" ])
      expect(item.reload).to have_attributes(status: "released", reviewed_by_id: reviewer.id)
      expect(Accounting::AuditLog.where(action: "document_mail_released").count).to eq(1)
    end

    it "discards a mail: nothing enters, the raw text is kept for the record" do
      item = quarantine_one

      PortalAdmin::ReviewMail.discard(item, by: reviewer)

      expect(documents).to be_empty
      expect(item.reload.status).to eq("discarded")
      expect(item.raw).to be_present
    end

    it "reviews a mail once" do
      item = quarantine_one
      PortalAdmin::ReviewMail.discard(item, by: reviewer)
      expect(PortalAdmin::ReviewMail.release(item, by: reviewer)).to be_failure
      expect(documents).to be_empty
    end
  end
end
