class ReplaceGlobalUniqueIndexesWithComposite < ActiveRecord::Migration[8.1]
  def up
    # accounting_accounts: code unique → (entity_id, code) unique
    remove_index :accounting_accounts, name: "index_accounting_accounts_on_code"
    add_index :accounting_accounts, %i[entity_id code], unique: true,
              name: "index_accounting_accounts_on_entity_and_code"

    # accounting_journals: code unique → (entity_id, code) unique
    remove_index :accounting_journals, name: "index_accounting_journals_on_code"
    add_index :accounting_journals, %i[entity_id code], unique: true,
              name: "index_accounting_journals_on_entity_and_code"

    # accounting_fiscal_years: year unique → (entity_id, year) unique
    remove_index :accounting_fiscal_years, name: "index_accounting_fiscal_years_on_year"
    add_index :accounting_fiscal_years, %i[entity_id year], unique: true,
              name: "index_accounting_fiscal_years_on_entity_and_year"

    # accounting_fiscal_years: one open globally → one open per entity
    remove_index :accounting_fiscal_years, name: "idx_accounting_fiscal_years_one_open"
    add_index :accounting_fiscal_years, :entity_id, unique: true,
              where: "status = 0",
              name: "idx_accounting_fiscal_years_one_open_per_entity"

    # accounting_journal_entries: reference unique → (entity_id, reference) unique where NOT NULL
    remove_index :accounting_journal_entries, name: "index_accounting_journal_entries_on_reference"
    add_index :accounting_journal_entries, %i[entity_id reference], unique: true,
              where: "reference IS NOT NULL",
              name: "index_accounting_journal_entries_on_entity_and_reference"

    # accounting_bank_accounts: iban unique → (entity_id, iban) unique
    remove_index :accounting_bank_accounts, name: "index_accounting_bank_accounts_on_iban"
    add_index :accounting_bank_accounts, %i[entity_id iban], unique: true,
              name: "index_accounting_bank_accounts_on_entity_and_iban"

    # accounting_analytical_axes: code unique → (entity_id, code) unique
    remove_index :accounting_analytical_axes, name: "index_accounting_analytical_axes_on_code"
    add_index :accounting_analytical_axes, %i[entity_id code], unique: true,
              name: "index_accounting_analytical_axes_on_entity_and_code"

    # accounting_invoices: invoice_number unique → (entity_id, invoice_number) unique where NOT NULL
    remove_index :accounting_invoices, name: "index_accounting_invoices_on_invoice_number_unique"
    add_index :accounting_invoices, %i[entity_id invoice_number], unique: true,
              where: "invoice_number IS NOT NULL",
              name: "index_accounting_invoices_on_entity_and_invoice_number"

    # accounting_partners: vat_number unique globally → (entity_id, vat_number) unique where NOT NULL
    remove_index :accounting_partners, name: "index_accounting_partners_on_vat_number_unique"
    add_index :accounting_partners, %i[entity_id vat_number], unique: true,
              where: "vat_number IS NOT NULL",
              name: "index_accounting_partners_on_entity_and_vat_number"
  end

  def down
    remove_index :accounting_accounts, name: "index_accounting_accounts_on_entity_and_code"
    add_index :accounting_accounts, :code, unique: true,
              name: "index_accounting_accounts_on_code"

    remove_index :accounting_journals, name: "index_accounting_journals_on_entity_and_code"
    add_index :accounting_journals, :code, unique: true,
              name: "index_accounting_journals_on_code"

    remove_index :accounting_fiscal_years, name: "index_accounting_fiscal_years_on_entity_and_year"
    add_index :accounting_fiscal_years, :year, unique: true,
              name: "index_accounting_fiscal_years_on_year"

    remove_index :accounting_fiscal_years, name: "idx_accounting_fiscal_years_one_open_per_entity"
    add_index :accounting_fiscal_years, :status, unique: true,
              where: "status = 0",
              name: "idx_accounting_fiscal_years_one_open"

    remove_index :accounting_journal_entries, name: "index_accounting_journal_entries_on_entity_and_reference"
    add_index :accounting_journal_entries, :reference, unique: true,
              name: "index_accounting_journal_entries_on_reference"

    remove_index :accounting_bank_accounts, name: "index_accounting_bank_accounts_on_entity_and_iban"
    add_index :accounting_bank_accounts, :iban, unique: true,
              name: "index_accounting_bank_accounts_on_iban"

    remove_index :accounting_analytical_axes, name: "index_accounting_analytical_axes_on_entity_and_code"
    add_index :accounting_analytical_axes, :code, unique: true,
              name: "index_accounting_analytical_axes_on_code"

    remove_index :accounting_invoices, name: "index_accounting_invoices_on_entity_and_invoice_number"
    add_index :accounting_invoices, :invoice_number, unique: true,
              where: "invoice_number IS NOT NULL",
              name: "index_accounting_invoices_on_invoice_number_unique"

    remove_index :accounting_partners, name: "index_accounting_partners_on_entity_and_vat_number"
    add_index :accounting_partners, :vat_number, unique: true,
              where: "vat_number IS NOT NULL",
              name: "index_accounting_partners_on_vat_number_unique"
  end
end
