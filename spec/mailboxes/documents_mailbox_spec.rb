require "rails_helper"

# Each entity has a secret address: what arrives there, as attachments, lands in its document inbox (F03).
RSpec.describe DocumentsMailbox, type: :mailbox do
  include_context "with entity"

  def address(for_entity = entity) = for_entity.documents_email

  def receive(to: address, from: "supplier@acme.example", subject: "Invoice March", &block)
    receive_inbound_email_from_mail(to: to, from: from, subject: subject, body: "Please find the invoice attached.", &block)
  end

  def documents = Accounting::Document.order(:id)

  it "puts each attachment in the inbox, as a document that came by e-mail" do
    receive do |mail|
      mail.add_file(filename: "invoice-1.pdf", content: sample_pdf("one"))
      mail.add_file(filename: "scan.png", content: sample_png)
    end

    expect(documents.pluck(:name)).to eq([ "invoice-1.pdf", "scan.png" ])
    expect(documents).to all(be_email)
    expect(documents).to all(be_inbox)
  end

  it "remembers who sent it, with what subject" do
    receive(from: "billing@acme.example", subject: "March invoice") { |mail| mail.add_file(filename: "i.pdf", content: sample_pdf("src")) }

    expect(documents.first.extracted_data["source"]).to include("email" => a_hash_including("from" => "billing@acme.example", "subject" => "March invoice"))
  end

  it "reads the documents afterwards, like any upload" do
    expect { receive { |mail| mail.add_file(filename: "i.pdf", content: sample_pdf("queue")) } }.to have_enqueued_job(Accounting::ExtractDocumentJob)
  end

  it "unpacks an archive" do
    archive = Accounting::Zipper.build([ [ "a.pdf", sample_pdf("a") ], [ "b.pdf", sample_pdf("b") ] ])

    receive { |mail| mail.add_file(filename: "invoices.zip", content: archive) }

    expect(documents.pluck(:name)).to contain_exactly("a.pdf", "b.pdf")
  end

  describe "pictures that are part of the message, not documents" do
    it "ignores a small inline image (a logo in a signature)" do
      receive do |mail|
        mail.attachments.inline["logo.png"] = { mime_type: "image/png", content: sample_png }
        mail.add_file(filename: "invoice.pdf", content: sample_pdf("real"))
      end

      expect(documents.pluck(:name)).to eq([ "invoice.pdf" ])
    end

    it "keeps an inline image once it is large enough to be a real picture (10 KB and more)" do
      big = sample_png("x" * 12_000) # a valid PNG, 12 KB
      receive { |mail| mail.attachments.inline["photo.png"] = { mime_type: "image/png", content: big } }

      expect(documents.pluck(:name)).to eq([ "photo.png" ])
    end

    it "keeps a small image that was attached as a file" do
      receive { |mail| mail.add_file(filename: "receipt.png", content: sample_png) }

      expect(documents.pluck(:name)).to eq([ "receipt.png" ])
    end
  end

  describe "what it refuses" do
    it "does nothing for an address nobody has (and does not answer: no reply to a stranger)" do
      expect { receive(to: "documents+nope@#{Rails.configuration.x.documents_mail_domain}") { |m| m.add_file(filename: "i.pdf", content: sample_pdf("x")) } }
        .not_to change(Accounting::Document, :count)
    end

    it "does nothing while the feature is off for the entity" do
      entity.update!(features: { "f03" => false })

      expect { receive { |mail| mail.add_file(filename: "i.pdf", content: sample_pdf("x")) } }.not_to change(Accounting::Document, :count)
    end

    it "keeps the files that are fine when others are not" do
      receive do |mail|
        mail.add_file(filename: "ok.pdf", content: sample_pdf("ok"))
        mail.add_file(filename: "evil.pdf", content: sample_exe)
      end

      expect(documents.pluck(:name)).to eq([ "ok.pdf" ])
    end

    it "does not create the same document twice when the same file comes again" do
      2.times { |i| receive(subject: "again #{i}") { |mail| mail.add_file(filename: "same.pdf", content: sample_pdf("same")) } }

      expect(documents.count).to eq(1)
    end

    it "does nothing with a message that has no attachment" do
      expect { receive }.not_to change(Accounting::Document, :count)
    end
  end

  describe "the address" do
    it "belongs to one entity: another entity's mail never lands here" do
      other = create(:entity)

      ActsAsTenant.with_tenant(other) { receive(to: address(other)) { |mail| mail.add_file(filename: "theirs.pdf", content: sample_pdf("theirs")) } }

      expect(documents.count).to eq(0)
      expect(ActsAsTenant.with_tenant(other) { Accounting::Document.pluck(:name) }).to eq([ "theirs.pdf" ])
    end

    it "is found whatever the case, and with other recipients on the message" do
      mail_to = address.upcase
      receive_inbound_email_from_mail(to: "someone@else.example, #{mail_to}", from: "a@b.example", subject: "x") { |mail| mail.add_file(filename: "i.pdf", content: sample_pdf("case")) }

      expect(documents.count).to eq(1)
    end

    it "stops working when the owner replaces it" do
      old = address
      entity.regenerate_documents_mail_token

      expect { receive(to: old) { |mail| mail.add_file(filename: "i.pdf", content: sample_pdf("old")) } }.not_to change(Accounting::Document, :count)
      expect { receive(to: address) { |mail| mail.add_file(filename: "j.pdf", content: sample_pdf("new")) } }.to change(Accounting::Document, :count).by(1)
    end
  end
end
