# Entities provisioned before the VAT prorata work (640400 "Non-deductible VAT")
# never received accounts added to the PCMN seed files afterwards. PcmnSeeder is
# idempotent (find_or_initialize_by code), so re-running it per entity only adds
# what's missing.
class BackfillPcmnAccountsForExistingEntities < ActiveRecord::Migration[8.1]
  def up
    Entity.find_each do |entity|
      ActsAsTenant.with_tenant(entity) { Seeders::PcmnSeeder.call(entity: entity) }
    end
  end

  def down
    # no-op: accounts may already be in use, never remove them
  end
end
