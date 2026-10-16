# B02b: where the document of an accepted upload stands in the firm, as the client may be told (written by the firm's side, never from the portal).
class AddProgressToPortalUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :portal_uploads, :progress, :string, null: false, default: "received"
  end
end
