class CreateEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :entities do |t|
      t.string  :name,         null: false
      t.string  :legal_name,   null: false
      t.string  :vat_number
      t.string  :country,      null: false, default: "BE"
      t.string  :legal_form
      t.string  :address_line1
      t.string  :address_line2
      t.string  :city
      t.string  :zip_code
      t.boolean :active,       null: false, default: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :entities, :vat_number, unique: true,
              where: "vat_number IS NOT NULL",
              name: "index_entities_on_vat_number_unique"
  end
end
