# Step 1: Seed users (entity needs a created_by user)
Seeders::UsersSeeder.call

# Step 2: Create default entity
admin_user = User.find_by!(email: "admin@ledgerflow.test")

entity = Entity.find_or_initialize_by(name: "LedgerFlow Demo ASBL")
if entity.new_record?
  entity.assign_attributes(
    legal_name:  "LedgerFlow Demo ASBL",
    legal_form:  "ASBL",
    country:     "BE",
    vat_number:  nil,
    active:      true,
    created_by:  admin_user
  )
  entity.save!
  puts "[Entity] '#{entity.name}' créée (id=#{entity.id})"
else
  puts "[Entity] '#{entity.name}' déjà présente, skipped."
end

# Step 3: Seed accounting data within entity context
ActsAsTenant.with_tenant(entity) do
  Seeders::PcmnSeeder.call(entity: entity)
  Seeders::JournalsSeeder.call

  bank_account = Accounting::BankAccount.find_or_initialize_by(iban: "BE68539007547034")
  if bank_account.new_record?
    bank_account.assign_attributes(
      journal:  Accounting::Journal.find_by!(code: "BNQ"),
      label_fr: "Compte principal",
      bic:      "BBRUBEBB",
      currency: "EUR",
      active:   true
    )
    bank_account.save!
    puts "[BankAccount] '#{bank_account.label_fr}' créé."
  end
  Seeders::AnalyticalAxesSeeder.call
  Seeders::PartnersSeeder.call

  # Create opening fiscal year if not already present
  current_year = Date.current.year
  unless Accounting::FiscalYear.exists?(year: current_year)
    Accounting::FiscalYear.create!(
      year:       current_year,
      start_date: Date.new(current_year, 1, 1),
      end_date:   Date.new(current_year, 12, 31),
      status:     :open
    )
    puts "[FiscalYear] Exercice #{current_year} créé."
  end

  # Opening balance on the main bank account: OD entry (550100 / 100000) + reconciled bank transaction
  unless bank_account.transactions.exists?(reference: "OPENING")
    fiscal_year = Accounting::FiscalYear.find_by!(year: current_year)
    amount      = BigDecimal("50000")

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

      journal = Accounting::Journal.find_by!(code: "OD")
      entry = Accounting::JournalEntry.create!(
        journal:     journal,
        fiscal_year: fiscal_year,
        entry_date:  fiscal_year.start_date,
        description: "Opening balance",
        reference:   journal.next_sequence_number(year: fiscal_year.start_date.year),
        status:      :draft
      )
      { "550100" => { debit: amount }, "100000" => { credit: amount } }.each do |code, side|
        entry.lines.create!(account: Accounting::Account.find_by!(code: code), label: "Opening balance", **side)
      end
      result = Accounting::PostJournalEntry.call(entry: entry)
      raise ActiveRecord::Rollback, result.message if result.failure?

      bank_account.transactions.create!(
        transaction_date: fiscal_year.start_date,
        amount:           amount,
        currency:         "EUR",
        description:      "Opening balance",
        reference:        "OPENING",
        status:           :reconciled,
        journal_entry:    entry,
        raw_data:         {}
      )
      puts "[BankAccount] Solde d'ouverture #{amount} € créé (écriture #{entry.reference})."
    end
  end
end

# Step 4: Create UserEntity memberships for all non-budget users
ROLE_MAP = { "admin" => :admin, "accountant" => :accountant, "manager" => :manager, "auditor" => :auditor }.freeze

User.where.not(role: User.roles[:budget_user]).find_each do |user|
  entity_role = ROLE_MAP[user.role]
  next unless entity_role

  unless UserEntity.exists?(user: user, entity: entity)
    UserEntity.create!(user: user, entity: entity, role: entity_role, active: true)
    puts "[UserEntity] #{user.email} → #{entity_role} on '#{entity.name}'"
  end
end
