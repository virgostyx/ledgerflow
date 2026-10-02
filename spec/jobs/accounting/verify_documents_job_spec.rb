require "rails_helper"

RSpec.describe Accounting::VerifyDocumentsJob, type: :job do
  include_context "with entity"

  let(:user) { create(:user) }

  def store(text) = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf(text)), filename: "#{text}.pdf", user: user)[:document]

  it "looks at every document of every entity, each in its own tenant" do
    mine = store("mine")
    other = create(:entity)
    theirs = ActsAsTenant.with_tenant(other) { store("theirs") }

    described_class.perform_now

    expect(mine.reload.integrity_status).to eq("ok")
    expect(ActsAsTenant.with_tenant(other) { Accounting::Document.find(theirs.id).integrity_status }).to eq("ok")
  end

  it "can be limited to one entity" do
    mine = store("mine")
    other = create(:entity)
    theirs = ActsAsTenant.with_tenant(other) { store("theirs") }

    described_class.perform_now(entity.id)

    expect(mine.reload.integrity_status).to eq("ok")
    expect(ActsAsTenant.with_tenant(other) { Accounting::Document.find(theirs.id).integrity_status }).to be_nil
  end

  it "reports what it checked and what it found wrong" do
    store("fine")
    broken = store("broken")
    tamper_with_stored_file(broken)

    summary = described_class.perform_now

    expect(summary).to include(checked: 2, failed: 1, errors: 0)
  end

  it "goes on after a document it could not read, and counts it" do
    store("one")
    store("two")
    calls = 0
    allow(Accounting::VerifyDocument).to receive(:call).and_wrap_original do |original, **args|
      calls += 1
      raise IOError, "storage down" if calls == 1

      original.call(**args)
    end

    summary = described_class.perform_now

    expect(summary).to include(checked: 2, errors: 1)
    expect(Accounting::Document.where(integrity_status: "ok").count).to eq(1)
  end

  it "does not call an unreachable storage a missing file" do
    doc = store("one")
    allow_any_instance_of(ActiveStorage::Blob).to receive(:download).and_raise(IOError, "storage down")

    described_class.perform_now

    expect(doc.reload.integrity_status).to be_nil
  end

  it "is scheduled every week in production" do
    require "fugit"
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "verify_documents")

    expect(schedule).to include("class" => "Accounting::VerifyDocumentsJob")
    expect(Fugit.parse(schedule["schedule"])).to be_a(Fugit::Cron)
  end
end
