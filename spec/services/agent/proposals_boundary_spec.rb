require "rails_helper"

# A07: no path lets the model create an entry or a task. The doors that write are few, and none is a tool or the loop of the agent; this spec reads the code to say so.
RSpec.describe "What may write on behalf of a proposal" do
  def files(pattern) = Dir[Rails.root.join(pattern)].select { |file| File.file?(file) }

  def mentions(names, pattern)
    files(pattern).select { |file| File.read(file).lines.reject { |line| line.strip.start_with?("#") }.join.match?(names) }.map { |file| file.sub("#{Rails.root}/", "") }
  end

  it "keeps the creation of a draft to the entry screen and to the click on a proposal" do
    expect(mentions(/CreateDraftEntry/, "app/**/*.rb")).to contain_exactly("app/controllers/accounting/journal_entries_controller.rb", "app/services/accounting/create_draft_entry.rb", "app/services/agent/proposals/accept.rb")
  end

  it "keeps the tools, the validators and the loop of the agent away from every service that writes entries or tasks" do
    writers = /CreateDraftEntry|PostJournalEntry|PostInvoice|ReverseJournalEntry|Accounting::Task\.(create|new)|JournalEntry\.(create|new)|Proposals::Accept/
    agent_files = %w[app/services/agent/tools/*.rb app/services/agent/proposals/entry.rb app/services/agent/proposals/task.rb app/services/agent/runner.rb app/services/agent/tool_registry.rb app/services/agent/model_gateway.rb]

    expect(agent_files.flat_map { |pattern| mentions(writers, pattern) }).to be_empty
  end

  it "reaches the click only from the controller of the person's own proposals" do
    expect(mentions(/Proposals::Accept\.call/, "app/**/*.rb")).to contain_exactly("app/controllers/agent/proposals_controller.rb")
  end
end
