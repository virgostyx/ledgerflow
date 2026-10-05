# F13b: the full backup of an entity (a ZIP built in the background, kept a few days, downloaded through a signed link).
# The standard exports are streamed and keep no file.
class CreateDataExports < ActiveRecord::Migration[8.1]
  def change
    create_table :data_exports do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string   :kind, null: false, default: "backup"
      t.string   :status, null: false, default: "processing" # processing / ready / failed / expired
      t.jsonb    :params, null: false, default: {}
      t.integer  :file_count, null: false, default: 0
      t.bigint   :bytes, null: false, default: 0
      t.string   :error
      t.datetime :expires_at
      t.timestamps
    end
  end
end
