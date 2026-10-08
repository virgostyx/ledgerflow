require "rails_helper"

# The catalog as a whole (A02): every tool is in it, nothing in it can write, and it stays small enough to send with every question.
RSpec.describe "The agent's tool catalog" do
  TOOL_FILES = Dir[Rails.root.join("app/services/agent/tools/*.rb")].reject { |file| File.basename(file) == "base.rb" }.sort.freeze

  # What a tool may use of the application: the reports (queries and services that read), and the models it reads from. Nothing that posts, letters, locks, imports, pays or sends.
  READ_ONLY_CONSTANTS = %w[Account Partner JournalEntry FiscalYear PeriodLock Journal TrialBalanceQuery GeneralLedgerQuery AgedBalanceQuery UnletteredLinesQuery BankAccount
                           BankReconciliationQuery AnnualAccounts VatGridQuery VatDeclaration DashboardKpis ConsistencyRun ConsistencyFinding ConsistencyAcknowledgement
                           AuditLogsQuery Document VariationQuery AuditLog Consistency Task DunningTexts DunningPolicy].freeze
  WRITE_CALL = /\.(create!?|update!?|update_all|update_column|update_columns|destroy!?|destroy_all|delete|delete_all|save!?|insert_all!?|upsert_all|touch|increment!|toggle!)\b|\bnew\.save|\.execute\(/
  OTHER_NAMESPACES = /\b(Closing|Payments|Imports|Fx|Peppol|Banking|Bank|Entities|Consolidation|Portfolio|Webhooks|Exports|Api)::[A-Z]/

  # What is wrong with the source of a tool, if anything: the same check is run on the real tools and on made-up ones, to show that it catches.
  def violations(source)
    code = source.lines.reject { |line| line.strip.start_with?("#") }.join
    found = []
    found << "calls a write: #{code[WRITE_CALL]}" if code.match?(WRITE_CALL)
    found << "uses another part of the application: #{code[OTHER_NAMESPACES]}" if code.match?(OTHER_NAMESPACES)
    found.concat(code.scan(/\bAccounting::(\w+)/).flatten.uniq.reject { |name| READ_ONLY_CONSTANTS.include?(name) }.map { |name| "uses Accounting::#{name}, which is not on the list of what a tool may read" })
    found
  end

  it "has tools to check" do
    expect(TOOL_FILES.size).to be >= 15
  end

  TOOL_FILES.each do |file|
    it "keeps #{File.basename(file)} to reading: no write call, nothing but the reports and the models it reads" do
      expect(violations(File.read(file))).to be_empty
    end
  end

  describe "the check itself" do
    it "catches a tool that posts an entry, creates a record, runs raw SQL or uses a service of another part" do
      expect(violations("Accounting::PostJournalEntry.call!(entry: entry)")).to include(a_string_matching(/not on the list/))
      expect(violations("Accounting::Partner.create!(name: 'x')")).to include(a_string_matching(/calls a write/))
      expect(violations("ActiveRecord::Base.connection.execute('DELETE FROM x')")).to include(a_string_matching(/calls a write/))
      expect(violations("Closing::Approve.call")).to include(a_string_matching(/another part/))
      expect(violations("Payments::Actions::CreateSettlementJournalEntry.call")).to include(a_string_matching(/another part/))
    end

    it "lets a plain read through, and ignores a comment that names a write" do
      expect(violations("# never Accounting::PostJournalEntry\nAccounting::Account.search(q).order(:code)")).to be_empty
    end
  end

  describe "the default registry" do
    let(:registry) { Agent::ToolRegistry.default }

    it "holds every tool of the directory, once" do
      expect(registry.definitions.map { |d| d[:name] }).to match_array(TOOL_FILES.map { |file| File.basename(file, ".rb") })
      expect(registry.definitions.map { |d| d[:name] }.uniq.size).to eq(registry.definitions.size)
    end

    it "stays compact: its definitions are sent with every question" do
      expect(registry.definitions.to_json.bytesize).to be < 34_000
    end

    it "is what the runner uses when it is not given another" do
      runner = Agent::Runner.new(conversation: instance_double(Agent::Conversation), context: instance_double(Agent::Context))

      expect(runner.instance_variable_get(:@registry).definitions).to eq(registry.definitions)
    end

    it "names only permissions that exist" do
      Agent::ToolRegistry.default.instance_variable_get(:@tools).each_value do |tool|
        expect { Permissions.allowed?(:admin, tool.permission) }.not_to raise_error
      end
    end
  end
end
