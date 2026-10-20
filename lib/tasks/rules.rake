namespace :rules do
  desc "Record an accountant's validation: rules:validate[entity_id,rule_key,name,title,reference] (rule_key: #{Accounting::RuleValidation::RULES.join(', ')}). Dated today."
  task :validate, %i[entity_id rule_key name title reference] => :environment do |_, args|
    entity = Entity.find(args[:entity_id])
    ActsAsTenant.with_tenant(entity) do
      Accounting::RuleValidation.create!(rule_key: args[:rule_key], validated_by_name: args[:name], validated_by_title: args[:title],
                                         reference: args[:reference], validated_on: Date.current)
    end
    puts "#{args[:rule_key]} validated by #{args[:name]} for #{entity.name}"
  end

  desc "Withdraw the validation in force: rules:revoke[entity_id,rule_key]"
  task :revoke, %i[entity_id rule_key] => :environment do |_, args|
    entity = Entity.find(args[:entity_id])
    ActsAsTenant.with_tenant(entity) { Accounting::RuleValidation.in_force.find_by!(rule_key: args[:rule_key]).revoke! }
    puts "#{args[:rule_key]} validation revoked for #{entity.name}"
  end
end
