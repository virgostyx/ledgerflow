require 'rails_helper'

# B02a: "the portal connects with a PostgreSQL role limited to its tables and views". The script that creates the role is generated from the tables that exist, so that a new portal
# table cannot be forgotten, and checked to name nothing of the books. (The suite's database user may not create roles: what the role really can do is verified at deployment,
# see docs/dev/signature/B02a.md.)
RSpec.describe PortalAdmin::DatabaseRole do
  let(:sql) { described_class.sql(role: 'ledgerflow_portal') }
  let(:portal_tables) { ApplicationRecord.connection.tables.grep(/\Aportal_/) }
  let(:named) { sql.scan(/\b(?:ON|TABLE|TABLES)\s+(?:TABLE\s+)?([a-z_]+(?:,\s*[a-z_]+)*)\s+(?:TO|FROM)/i).flatten.flat_map { |list| list.split(/,\s*/) } }

  it 'reads every table and view of the portal, and the view of the companies' do
    (portal_tables + [ 'portal_companies' ]).uniq.each do |table|
      expect(sql).to match(/GRANT SELECT[^;]*\b#{table}\b/), "#{table} is not readable by the portal role"
    end
  end

  it 'names nothing outside the portal but the bookkeeping of the migrations' do
    outside = named.reject { |name| name.start_with?('portal_') } - %w[schema_migrations ar_internal_metadata]
    expect(outside).to be_empty
    expect(sql.lines.grep(/\AGRANT/).join).not_to match(/ALL TABLES|ALL SEQUENCES|ALL PRIVILEGES|TO PUBLIC|WITH GRANT OPTION/i)
    expect(sql).to include('NOSUPERUSER NOCREATEDB NOCREATEROLE')
  end

  it 'writes only where the portal has something to write: its sessions, devices, events, requests, uploads, its own people' do
    writable = sql.scan(/GRANT (?:INSERT|UPDATE|DELETE)[A-Z, ]* ON (\w+) TO/).flatten
    expect(writable).to match_array(%w[portal_users portal_backup_codes portal_grants portal_invitations portal_sessions portal_devices portal_events portal_access_requests portal_uploads portal_upload_chunks portal_document_request_lines])
  end

  it 'never lets the portal change what the firm published, nor delete a grant or an event' do
    expect(sql).not_to match(/(?:INSERT|UPDATE|DELETE)[A-Z, ]* ON portal_(publications|publication_files|publication_recipients|brandings)\b/)
    expect(sql).not_to match(/DELETE[A-Z, ]* ON portal_(grants|events|sessions)\b/)
  end

  it 'refuses a role name that is not a plain identifier' do
    expect { described_class.sql(role: 'x; DROP TABLE users') }.to raise_error(ArgumentError)
  end

  it 'asks the password at deployment, not here' do
    expect(sql).to include('PASSWORD :')
    expect(sql).not_to match(/PASSWORD '/)
  end
end
