# F04: kind, reason and automatic mark of a lettering, and the history of every lettering and unlettering of a line. A lettering is
# deleted when undone (its lines go free); its history stays, one row per line and per event.
class AddHistoryToLetterings < ActiveRecord::Migration[8.1]
  def change
    change_table :accounting_letterings do |t|
      t.string  :kind, null: false, default: "full" # full / partial / write_off
      t.boolean :auto, null: false, default: false
      t.string  :reason
      t.references :lettered_by, foreign_key: { to_table: :users }
    end

    create_table :accounting_lettering_events do |t|
      t.references :entity, null: false, foreign_key: true
      t.bigint :line_id, null: false
      t.string :action, null: false # letter / unletter
      t.string :code, null: false
      t.references :user, foreign_key: true
      t.boolean :auto, null: false, default: false
      t.string :reason
      t.timestamps
    end
    add_index :accounting_lettering_events, %i[entity_id line_id]
  end
end
