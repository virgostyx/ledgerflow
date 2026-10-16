namespace :portal do
  desc "Prints the SQL that creates the restricted PostgreSQL role of the client portal (ROLE=ledgerflow_portal)"
  task database_role: :environment do
    puts PortalAdmin::DatabaseRole.sql(role: ENV.fetch("ROLE", "ledgerflow_portal"))
  end
end
