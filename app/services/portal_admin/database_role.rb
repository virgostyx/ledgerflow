# B02a: the PostgreSQL role the portal connects with, limited to its own tables and views. The script is generated from the tables that exist (a new portal table is read by
# default and written by no one until it is listed here), and printed by `bin/rails portal:database_role`.
class PortalAdmin::DatabaseRole
  # What the portal writes (privileges per table). Everything else of the portal is read-only for it: the publications, their files, the brandings, the companies.
  WRITES = {
    "portal_users"           => %w[UPDATE],
    "portal_backup_codes"    => %w[INSERT UPDATE DELETE],
    "portal_grants"          => %w[INSERT], # written when an invitation is accepted; never changed or deleted by the portal
    "portal_invitations"     => %w[UPDATE],
    "portal_sessions"        => %w[INSERT UPDATE],
    "portal_devices"         => %w[INSERT UPDATE],
    "portal_events"          => %w[INSERT],
    "portal_access_requests" => %w[INSERT]
  }.freeze
  BOOKKEEPING = %w[schema_migrations ar_internal_metadata].freeze

  def self.sql(role: "ledgerflow_portal")
    raise ArgumentError, "not a role name" unless role.match?(/\A[a-z][a-z0-9_]{0,62}\z/)

    tables = (ApplicationRecord.connection.tables.grep(/\Aportal_/) + ApplicationRecord.connection.views.grep(/\Aportal_/)).uniq.sort
    lines = [
      "-- Role of the client portal (B02a). Run as the owner of the database, with the password given on the command line: psql -v pw=... -f this-file",
      "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{role}') THEN CREATE ROLE #{role} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT; END IF; END $$;",
      "ALTER ROLE #{role} PASSWORD :'pw';",
      "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM #{role};",
      "GRANT USAGE ON SCHEMA public TO #{role};",
      "GRANT SELECT ON #{(tables + BOOKKEEPING).join(', ')} TO #{role};"
    ]
    WRITES.each do |table, privileges|
      lines << "GRANT #{privileges.join(', ')} ON #{table} TO #{role};"
      lines << "GRANT USAGE ON SEQUENCE #{table}_id_seq TO #{role};" if privileges.include?("INSERT")
    end
    lines.join("\n") << "\n"
  end
end
