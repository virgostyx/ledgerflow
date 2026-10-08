require "rails_helper"

# A09: a reading starts on a person's action only, nothing is confirmed by the assistant, and the call to the model has no other tool. This spec reads the code to say so.
RSpec.describe "What starts and what confirms a reading of a document" do
  def mentions(pattern, glob)
    Dir[Rails.root.join(glob)].select { |file| File.read(file).lines.reject { |line| line.strip.start_with?("#") }.join.match?(pattern) }.map { |file| file.sub("#{Rails.root}/", "") }
  end

  it "starts a reading only from the controller of the person and from the batch job that controller queues" do
    expect(mentions(/Documents::Extract\.call/, "app/**/*.rb")).to contain_exactly("app/controllers/agent/document_extractions_controller.rb", "app/jobs/agent/document_batch_job.rb")
    expect(mentions(/DocumentBatchJob/, "app/**/*.rb")).to contain_exactly("app/controllers/agent/document_extractions_controller.rb", "app/jobs/agent/document_batch_job.rb")
  end

  it "does not start one when a document arrives: no callback, no upload service, no mail or Peppol reception reads a document with the model" do
    arrivals = %w[app/models/accounting/document.rb app/services/accounting/upload_document.rb app/services/accounting/extract_document.rb app/services/peppol/*.rb app/jobs/accounting/*.rb]

    expect(arrivals.flat_map { |glob| mentions(/Agent::/, glob) }).to be_empty
  end

  it "confirms a field only when a person clicks: the reading, the tools and the jobs never call the door of F03" do
    expect(mentions(/ConfirmDocumentField\.call/, "app/**/*.rb")).to contain_exactly("app/controllers/accounting/documents_controller.rb", "app/controllers/agent/document_extractions_controller.rb")
    expect(mentions(/ConfirmDocumentField/, "app/services/agent/**/*.rb")).to contain_exactly("app/services/agent/documents/normalize.rb")
  end

  it "gives the model reading a document one tool, and no other, in the definition and in the call" do
    expect(Agent::Documents::Submission.definition[:name]).to eq("submit_extraction")
    reading = File.read(Rails.root.join("app/services/agent/documents/reading.rb"))
    expect(reading).to include("tools: [ Agent::Documents::Submission.definition ]", "tool_choice: Agent::Documents::Submission.tool_choice")
    expect(reading).not_to include("ToolRegistry")
  end
end
