namespace :audit do
  desc "Recompute the audit hash chain of every entity and name the first broken row"
  task verify: :environment do
    broken = false
    Entity.find_each do |entity|
      result = Accounting::AuditVerifier.call(entity: entity)
      if result.intact?
        puts "[audit] #{entity.name}: intact on #{result.count} entries"
      else
        broken = true
        puts "[audit] #{entity.name}: BROKEN at entry ##{result.broken_id} (#{result.count} entries verified before it)"
      end
    end
    exit(1) if broken
  end
end
