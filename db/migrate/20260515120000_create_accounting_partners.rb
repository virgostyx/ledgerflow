class CreateAccountingPartners < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_partners do |t|
      t.string  :name,         null: false
      t.integer :partner_type, null: false, default: 0
      t.string  :vat_number
      t.string  :email
      t.string  :phone
      t.string  :street
      t.string  :city
      t.string  :zip
      t.string  :country, null: false, default: 'BE'
      t.string  :iban
      t.string  :bic
      t.boolean :active, null: false, default: true
      t.text    :notes
      t.timestamps
    end

    add_index :accounting_partners, :partner_type
    add_index :accounting_partners, :vat_number, unique: true,
              where: 'vat_number IS NOT NULL', name: 'index_accounting_partners_on_vat_number_unique'
    add_index :accounting_partners, :active
  end
end
