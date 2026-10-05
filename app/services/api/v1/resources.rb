# F13c: the read-only resources of the public API, described once: what it is called, which scope reads it, how a row is written out, how it can be
# filtered and sorted. The routes, the controller and the OpenAPI document are all made from this, so that they cannot disagree.
module Api::V1::Resources
  Resource = Data.define(:name, :scope, :description, :relation, :fields, :filters, :sorts)

  def self.date_between(column) = ->(scope, value) { scope.where("#{column} = ?", value) }

  REGISTRY = {
    "accounts" => Resource.new(
      name: "accounts", scope: "accounts:read", description: "The chart of accounts.",
      relation: -> { Accounting::Account.all },
      fields: { "id" => :integer, "code" => :string, "label_fr" => :string, "label_nl" => :string, "account_type" => :string, "normal_balance" => :string,
                "account_class" => :integer, "reconcilable" => :boolean, "active" => :boolean, "currency" => :string },
      filters: { "code" => ->(s, v) { s.where("accounting_accounts.code LIKE ?", "#{Accounting::Account.sanitize_sql_like(v)}%") }, "account_type" => ->(s, v) { s.where(account_type: v) },
                 "account_class" => ->(s, v) { s.where(account_class: v) }, "active" => ->(s, v) { s.where(active: ActiveModel::Type::Boolean.new.cast(v)) } },
      sorts: { "id" => "accounting_accounts.id", "code" => "accounting_accounts.code" }
    ),
    "partners" => Resource.new(
      name: "partners", scope: "partners:read", description: "Customers and suppliers.",
      relation: -> { Accounting::Partner.all },
      fields: { "id" => :integer, "name" => :string, "partner_type" => :string, "vat_number" => :string, "email" => :string, "country" => :string, "iban" => :string,
                "payment_terms_days" => :integer, "external_ref" => :string, "language" => :string, "currency" => :string, "active" => :boolean },
      filters: { "partner_type" => ->(s, v) { s.where(partner_type: v) }, "vat_number" => ->(s, v) { s.where(vat_number: v) }, "external_ref" => ->(s, v) { s.where(external_ref: v) },
                 "name" => ->(s, v) { s.where("accounting_partners.name ILIKE ?", "%#{Accounting::Partner.sanitize_sql_like(v)}%") }, "active" => ->(s, v) { s.where(active: ActiveModel::Type::Boolean.new.cast(v)) } },
      sorts: { "id" => "accounting_partners.id", "name" => "accounting_partners.name" }
    ),
    "journals" => Resource.new(
      name: "journals", scope: "journals:read", description: "The journals.",
      relation: -> { Accounting::Journal.all },
      fields: { "id" => :integer, "code" => :string, "label_fr" => :string, "journal_type" => :string, "sequence_prefix" => :string, "active" => :boolean },
      filters: { "journal_type" => ->(s, v) { s.where(journal_type: v) }, "active" => ->(s, v) { s.where(active: ActiveModel::Type::Boolean.new.cast(v)) } },
      sorts: { "id" => "accounting_journals.id", "code" => "accounting_journals.code" }
    ),
    "documents" => Resource.new(
      name: "documents", scope: "documents:read", description: "The supporting documents (their description; the file itself is not served).",
      relation: -> { Accounting::Document.all },
      fields: { "id" => :integer, "name" => :string, "content_type" => :string, "byte_size" => :integer, "sha256" => :string, "origin" => :string, "kind" => :string,
                "status" => :string, "created_at" => :datetime },
      filters: { "kind" => ->(s, v) { s.where(kind: v) }, "status" => ->(s, v) { s.where(status: v) }, "sha256" => ->(s, v) { s.where(sha256: v) } },
      sorts: { "id" => "accounting_documents.id", "created_at" => "accounting_documents.created_at" }
    ),
    "bank_transactions" => Resource.new(
      name: "bank_transactions", scope: "bank:read", description: "The lines of the bank statements.",
      relation: -> { Accounting::BankTransaction.all },
      fields: { "id" => :integer, "bank_account_id" => :integer, "transaction_date" => :date, "value_date" => :date, "amount" => :decimal, "currency" => :string,
                "description" => :string, "reference" => :string, "counterparty_name" => :string, "counterparty_iban" => :string, "structured_communication" => :string,
                "status" => :string, "journal_entry_id" => :integer },
      filters: { "status" => ->(s, v) { s.where(status: v) }, "bank_account_id" => ->(s, v) { s.where(bank_account_id: v) },
                 "date" => ->(s, v) { s.where(transaction_date: v) } },
      sorts: { "id" => "accounting_bank_transactions.id", "transaction_date" => "accounting_bank_transactions.transaction_date" }
    ),
    "bank_statements" => Resource.new(
      name: "bank_statements", scope: "bank:read", description: "The imported bank statements, with their balances.",
      relation: -> { Accounting::BankStatement.all },
      fields: { "id" => :integer, "bank_account_id" => :integer, "sequence" => :integer, "old_balance_date" => :date, "old_balance" => :decimal, "new_balance_date" => :date,
                "new_balance" => :decimal, "status" => :string },
      filters: { "bank_account_id" => ->(s, v) { s.where(bank_account_id: v) }, "status" => ->(s, v) { s.where(status: v) } },
      sorts: { "id" => "accounting_bank_statements.id" }
    ),
    "tasks" => Resource.new(
      name: "tasks", scope: "tasks:read", description: "The tasks.",
      relation: -> { Accounting::Task.all },
      fields: { "id" => :integer, "title" => :string, "description" => :string, "status" => :string, "priority" => :string, "kind" => :string, "assignee_id" => :integer,
                "due_on" => :date, "target_type" => :string, "target_id" => :integer },
      filters: { "status" => ->(s, v) { s.where(status: v) }, "kind" => ->(s, v) { s.where(kind: v) }, "assignee_id" => ->(s, v) { s.where(assignee_id: v) } },
      sorts: { "id" => "accounting_tasks.id", "created_at" => "accounting_tasks.created_at" }
    ),
    "period_locks" => Resource.new(
      name: "period_locks", scope: "periods:read", description: "The period locks.",
      relation: -> { Accounting::PeriodLock.all },
      fields: { "id" => :integer, "kind" => :string, "status" => :string, "starts_on" => :date, "ends_on" => :date, "locked_at" => :datetime, "lock_reason" => :string,
                "unlocked_at" => :datetime },
      filters: { "status" => ->(s, v) { s.where(status: v) }, "kind" => ->(s, v) { s.where(kind: v) } },
      sorts: { "id" => "accounting_period_locks.id", "starts_on" => "accounting_period_locks.starts_on" }
    ),
    "letterings" => Resource.new(
      name: "letterings", scope: "letterings:read", description: "The letterings (matched lines of an account).",
      relation: -> { Accounting::Lettering.includes(:account) },
      fields: { "id" => :integer, "code" => :string, "account_id" => :integer, "partner_id" => :integer, "lettered_on" => :date, "kind" => :string, "auto" => :boolean },
      filters: { "account_id" => ->(s, v) { s.where(account_id: v) }, "partner_id" => ->(s, v) { s.where(partner_id: v) } },
      sorts: { "id" => "accounting_letterings.id", "lettered_on" => "accounting_letterings.lettered_on" }
    )
  }.freeze

  # Rows are written out from their attributes: the enums by their names, amounts as text (no float), dates as ISO.
  def self.serialize(resource, record)
    resource.fields.keys.to_h { |field| [ field, value(record.public_send(field)) ] }
  end

  def self.value(raw)
    case raw
    when BigDecimal then raw.to_s("F")
    when Date, Time, ActiveSupport::TimeWithZone then raw.iso8601
    else raw
    end
  end
end
