require "rails_helper"

# The capability table of docs/dev/features/spec.md §4, written as the spec writes it, independently of the matrix.
# Columns: Owner = admin, Accountant, Assistant, Reader = manager, External auditor = auditor.
RSpec.describe "Permissions::MATRIX against the F01 capability table" do
  OWNER, ACCOUNTANT, ASSISTANT, READER, EXTERNAL_AUDITOR = %i[admin accountant assistant manager auditor].freeze

  TABLE = {
    "Consult the reports"               => { roles: [ OWNER, ACCOUNTANT, ASSISTANT, READER, EXTERNAL_AUDITOR ], permissions: %w[reports.view] },
    "Enter drafts"                      => { roles: [ OWNER, ACCOUNTANT, ASSISTANT ], permissions: %w[records.write] },
    "Validate an entry"                 => { roles: [ OWNER, ACCOUNTANT ], permissions: %w[entries.post invoices.issue] },
    "Reverse a validated entry"         => { roles: [ OWNER, ACCOUNTANT ], permissions: %w[entries.reverse] },
    "Letter and reconcile"              => { roles: [ OWNER, ACCOUNTANT, ASSISTANT ], permissions: %w[reconciliations.manage] },
    "Lock a period"                     => { roles: [ OWNER, ACCOUNTANT ], permissions: %w[periods.lock] },
    "Unlock a period"                   => { roles: [ OWNER ], permissions: %w[periods.unlock] },
    "Manage chart of accounts, VAT, journals" => { roles: [ OWNER, ACCOUNTANT ], permissions: %w[settings.manage vat.file] },
    "Manage users and roles"            => { roles: [ OWNER ], permissions: %w[users.manage] },
    "Export"                            => { roles: [ OWNER, ACCOUNTANT, ASSISTANT ], permissions: %w[reports.export] },
    "Export, when the entity allows it" => { roles: [ READER, EXTERNAL_AUDITOR ], permissions: %w[reports.export_readonly] },
    "Import a bank statement (F02)"     => { roles: [ OWNER, ACCOUNTANT ], permissions: %w[bank.import] },
    "Match bank lines (F02)"            => { roles: [ OWNER, ACCOUNTANT, ASSISTANT ], permissions: %w[bank.match] },
    "Ask the AI agent (the external auditor only when an owner grants it, by a custom role)" => { roles: [ OWNER, ACCOUNTANT, ASSISTANT, READER ], permissions: %w[agent.use] },
    "Have the AI agent prepare proposals" => { roles: [ OWNER, ACCOUNTANT, ASSISTANT ], permissions: %w[agent.propose] },
    "Manage the file notes and the knowledge base of the AI agent" => { roles: [ OWNER, ACCOUNTANT ], permissions: %w[agent.memory.manage knowledge.manage] },
    "Configure the AI agent and review a conversation (exceptional access)" => { roles: [ OWNER ], permissions: %w[agent.configure agent.conversations.review] },
    "Consult the audit trail"           => { roles: [ OWNER, ACCOUNTANT, EXTERNAL_AUDITOR ], permissions: %w[audit.view] }
  }.freeze

  it "knows exactly the five roles of the spec" do
    expect(UserEntity.roles.keys.map(&:to_sym)).to match_array([ OWNER, ACCOUNTANT, ASSISTANT, READER, EXTERNAL_AUDITOR ])
  end

  TABLE.each do |capability, row|
    row[:permissions].each do |permission|
      it "grants '#{capability}' (#{permission}) to #{row[:roles].join(', ')} and to nobody else" do
        granted = UserEntity.roles.keys.map(&:to_sym).select { |role| Permissions.allowed?(role, permission) }

        expect(granted).to match_array(row[:roles])
      end
    end
  end

  it "lets every role read records (a read-only role still browses what the reports lead to)" do
    expect(UserEntity.roles.keys.map(&:to_sym).all? { |role| Permissions.allowed?(role, "records.list") && Permissions.allowed?(role, "records.view") }).to be true
  end
end
