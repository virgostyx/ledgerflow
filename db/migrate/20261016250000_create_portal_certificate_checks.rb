# B02c: what the firm's side last found about the integrity certificate (B03c) attached to a publication, so that the portal can say it without ever calling the verification itself.
class CreatePortalCertificateChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_certificate_checks do |t|
      t.references :publication, null: false, foreign_key: { to_table: :portal_publications }, index: { unique: true }
      t.string :state, null: false # valid, revoked, not_valid, unknown
      t.datetime :checked_at, null: false
      t.timestamps
    end
  end
end
