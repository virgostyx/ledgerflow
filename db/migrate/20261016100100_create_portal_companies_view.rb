# B02a: the one thing the portal reads of a company: its name, whether it is active and whether the portal is on for it. A view, so that the portal code reads portal_*
# only (and the database role of the portal can be limited to them).
class CreatePortalCompaniesView < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIEW portal_companies AS
        SELECT id, name, active, COALESCE((features ->> 'b02a')::boolean, false) AS portal_enabled
        FROM entities
    SQL
  end

  def down = execute("DROP VIEW portal_companies")
end
