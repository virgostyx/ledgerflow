# B03c: the settings of the owner for the integrity certificates: the timestamp authority (RFC 3161: its address and its certificate, to check what it answers), the level
# of disclosure proposed by default, and whether the public page of a certificate may name the company.
class AddIntegritySettingsToEntities < ActiveRecord::Migration[8.1]
  def change
    change_table :entities, bulk: true do |t|
      t.string :timestamp_authority_url
      t.text :timestamp_authority_ca
      t.string :integrity_default_disclosure, null: false, default: "standard"
      t.boolean :integrity_public_company_name, null: false, default: false
    end
  end
end
