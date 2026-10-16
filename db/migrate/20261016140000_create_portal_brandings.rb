# B02a: the look of the portal and of its e-mails, in the name of the firm: a display name, two colours (refused below the WCAG AA contrast), the name that signs the e-mails and a
# small logo (PNG or JPEG only: an SVG can carry script). One per company; the portal falls back to a neutral look.
class CreatePortalBrandings < ActiveRecord::Migration[8.1]
  def change
    create_table :portal_brandings do |t|
      t.references :entity, null: false, foreign_key: true, index: { unique: true }
      t.string :display_name, null: false
      t.string :primary_color, null: false, default: "#1f2937"
      t.string :background_color, null: false, default: "#f9fafb"
      t.string :sender_name
      t.binary :logo
      t.string :logo_content_type
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
