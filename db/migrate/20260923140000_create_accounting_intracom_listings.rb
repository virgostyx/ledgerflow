class CreateAccountingIntracomListings < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_intracom_listings do |t|
      t.references :entity,      null: false, foreign_key: true
      t.references :fiscal_year, null: false, foreign_key: { to_table: :accounting_fiscal_years }
      t.date    :period_start, null: false
      t.date    :period_end,   null: false
      t.integer :status,       null: false, default: 0 # draft: 0, submitted: 1

      t.timestamps
    end

    create_table :accounting_intracom_listing_lines do |t|
      t.references :entity,            null: false, foreign_key: true
      t.references :intracom_listing,  null: false, foreign_key: { to_table: :accounting_intracom_listings }
      t.references :partner,           null: false, foreign_key: { to_table: :accounting_partners }
      t.string  :code, null: false # "L" goods, "S" services
      t.decimal :amount, precision: 15, scale: 2, null: false

      t.timestamps
    end
  end
end
