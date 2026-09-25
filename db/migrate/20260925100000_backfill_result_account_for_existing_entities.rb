# The result account (699000, Accounting::AccountCodes::RESULT) was in neither PCMN seed file, so entities
# provisioned so far cannot close a fiscal year (Accounting::CloseFiscalYear looks it up). PcmnSeeder is idempotent
# (find_or_initialize_by code), so re-running it per entity only adds what is missing.
class BackfillResultAccountForExistingEntities < ActiveRecord::Migration[8.1]
  def up
    Entity.find_each do |entity|
      ActsAsTenant.with_tenant(entity) { Seeders::PcmnSeeder.call(entity: entity) }
    end
  end

  def down
    # no-op: accounts may already be in use, never remove them
  end
end
