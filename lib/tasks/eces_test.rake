# Creates the test company "ECES test" (PRODEM ZAMBIA is a PROJ analytical account pushed by BudgetFlow, not a company).
# Preview (changes nothing):  bin/rails "eces_test:create[owner@example.com]"
# Create:                     APPLY=1 bin/rails "eces_test:create[owner@example.com]"
# Production: bin/kamal app exec --interactive "APPLY=1 bin/rails 'eces_test:create[owner@example.com]'"
# Bank accounts, the ZMW cash journal and the BudgetFlow API client are made in the screens afterwards (see
# docs/dev/api/TEST_BUDGETFLOW_PRODEM_2.md).
namespace :eces_test do
  desc "Creates the company 'ECES test' (Fondation chart, 2026 fiscal year, quarterly VAT, BudgetFlow on)"
  task :create, %i[owner_email] => :environment do |_, args|
    name = "ECES test"
    features = %w[f01 f02 f03 f08 f11 f13 b01a b01b]
    owner = User.find_by(email: args[:owner_email].to_s.downcase) or abort "No user #{args[:owner_email].inspect}: give the e-mail of an existing account."
    abort "An entity named #{name.inspect} exists already (id #{Entity.find_by(name: name).id}): nothing changed." if Entity.exists?(name: name)

    attrs = { name: name, legal_name: "European Centre for Electoral Support (test)", country: "BE", legal_form: "Fondation",
              vat_regime: :normal, vat_filing_frequency: :quarterly, iban_cooling_hours: 0, budgetflow_enabled: true,
              features: features.index_with { true }, created_by: owner }
    puts "Will create #{name.inspect} for #{owner.email} in #{Rails.env}: #{attrs.except(:created_by).inspect}"
    abort "Preview only. Add APPLY=1 to create it." unless ENV["APPLY"] == "1"

    entity = Entity.create!(attrs)
    result = Entities::ProvisionEntity.call(entity: entity, created_by: owner)
    unless result.success?
      entity.destroy
      abort "Provisioning failed, entity removed: #{result.message}"
    end
    puts "Created entity #{entity.id}. Next: sign in, choose it, then follow section A of docs/dev/api/TEST_BUDGETFLOW_PRODEM_2.md."
  end
end
