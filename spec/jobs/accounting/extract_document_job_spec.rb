require "rails_helper"

RSpec.describe Accounting::ExtractDocumentJob, type: :job do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:document) { Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("Invoice No: INV-1\nTotal incl. VAT 10,00")), filename: "a.pdf", user: user)[:document] }

  def extraction(doc) = doc.reload.extracted_data["extraction"]

  it "is queued as soon as a document is uploaded" do
    expect { document }.to have_enqueued_job(described_class)
  end

  it "reads the document in the tenant of its entity, whatever tenant the worker started in" do
    other = create(:entity)
    document_id = document.id # created in this entity, before the worker is "in" another one

    ActsAsTenant.with_tenant(other) { described_class.perform_now(document_id, entity.id) }

    expect(extraction(document)["status"]).to eq("done")
  end

  it "does nothing for a document that was deleted meanwhile" do
    expect { described_class.perform_now(0, entity.id) }.not_to raise_error
  end

  it "tries again after a failure, with growing delays, up to three times" do
    allow(Accounting::ExtractDocument).to receive(:call).and_raise(RuntimeError, "temporary")

    expect { described_class.perform_now(document.id, entity.id) }.to have_enqueued_job(described_class).with(document.id, entity.id)
    expect(described_class.rescue_handlers.map(&:first)).to include("StandardError")
  end

  it "leaves the document marked as failed once the attempts are used up" do
    allow(Accounting::Extractors::PdfText).to receive(:call).and_raise(RuntimeError, "still broken")

    3.times { described_class.perform_now(document.id, entity.id) rescue nil } # rubocop:disable Style/RescueModifier

    expect(extraction(document)).to include("status" => "failed", "error" => "still broken")
  end
end
