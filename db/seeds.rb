require_relative 'seeders/pcmn_seeder'
require_relative 'seeders/journals_seeder'
require_relative 'seeders/analytical_axes_seeder'
require_relative 'seeders/users_seeder'

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
  Seeders::PcmnSeeder.call
  Seeders::JournalsSeeder.call
  Seeders::AnalyticalAxesSeeder.call

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
