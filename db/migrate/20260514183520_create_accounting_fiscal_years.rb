class CreateAccountingFiscalYears < ActiveRecord::Migration[8.1]
  def change
    create_table :accounting_fiscal_years do |t|
      t.integer  :year,            null: false
      t.date     :start_date,      null: false
      t.date     :end_date,        null: false
      t.integer  :status,          null: false, default: 0  # open/pre_closing/closed
      t.decimal  :opening_balance, precision: 15, scale: 2, default: 0
      t.datetime :closed_at
      t.bigint   :closed_by_id
      t.timestamps
    end

    add_index :accounting_fiscal_years, :year, unique: true

    # Un seul exercice open à la fois
    add_index :accounting_fiscal_years, :status,
              unique: true,
              where: "status = 0",
              name: "idx_accounting_fiscal_years_one_open"

    # start_date < end_date
    execute <<~SQL
      ALTER TABLE accounting_fiscal_years
        ADD CONSTRAINT chk_fiscal_year_dates
        CHECK (start_date < end_date);
    SQL
  end
end
