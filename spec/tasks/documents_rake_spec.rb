require "rails_helper"
require "rake"

RSpec.describe "documents rake tasks" do
  include_context "with entity"

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("documents:verify") }

  let(:user) { create(:user) }

  def run(task, env = {})
    Rake::Task[task].reenable
    env.each { |key, value| ENV[key.to_s] = value.to_s }
    Rake::Task[task].invoke
  ensure
    env.each_key { |key| ENV.delete(key.to_s) }
  end

  def store(text) = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf(text)), filename: "#{text}.pdf", user: user)[:document]

  it "documents:verify checks every stored file and says so" do
    store("a")
    store("b")

    expect { run("documents:verify") }.to output(/#{Regexp.escape(entity.name)}: 2 documents checked, 0 failed/).to_stdout
  end

  it "documents:verify names the document whose file no longer matches, and fails" do
    broken = store("broken")
    tamper_with_stored_file(broken)

    expect { expect { run("documents:verify") }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) } }
      .to output(/broken\.pdf: mismatch/).to_stdout
  end

  it "documents:verify names a missing file" do
    gone = store("gone")
    delete_stored_file(gone)

    expect { expect { run("documents:verify") }.to raise_error(SystemExit) }.to output(/gone\.pdf: missing/).to_stdout
  end

  it "documents:verify can be limited to one entity" do
    store("mine")
    other = create(:entity)
    ActsAsTenant.with_tenant(other) { store("theirs") }

    expect { run("documents:verify", ENTITY_ID: entity.id) }.to output(/1 documents checked/).to_stdout
  end

  it "documents:import_invoice_attachments brings the UBL and PDF kept on invoices into the store" do
    invoice = create(:invoice, :draft, invoice_type: :supplier, partner: create(:partner, :supplier))
    invoice.pdf_document.attach(io: StringIO.new(sample_pdf("old")), filename: "old.pdf", content_type: "application/pdf")

    expect { run("documents:import_invoice_attachments") }.to output(/#{Regexp.escape(entity.name)}: 1 imported, 0 refused/).to_stdout
  end
end
