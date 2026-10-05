# F13b: what each column of the standard exports holds. docs/exports.md is this, as text (a spec fails when they differ; regenerate with
# `bin/rails exports:docs`).
module Exports::Dictionary
  COLUMNS = {
    "entries" => {
      "entry_id" => "Identifier of the entry", "reference" => "Number given when the entry was validated (empty for a draft)", "entry_date" => "Date of the entry, YYYY-MM-DD",
      "journal" => "Code of the journal", "status" => "draft, posted or reversed", "fiscal_year" => "Year of the fiscal year", "description" => "Description of the entry",
      "external_id" => "Key of the piece in the file it was imported from (F13a)", "line_id" => "Identifier of the line", "account" => "Code of the account",
      "partner" => "Name of the partner on the line", "partner_vat" => "VAT number of that partner", "label" => "Label of the line", "debit" => "Debit in EUR, two decimals",
      "credit" => "Credit in EUR, two decimals", "currency" => "Currency of the line (EUR unless the line is in a foreign currency)",
      "amount_currency" => "Amount in that currency, signed (debit positive); empty in EUR", "exchange_rate" => "Units of that currency for 1 EUR; empty in EUR"
    },
    "accounts" => {
      "code" => "Code of the account", "label_fr" => "Label in French", "label_nl" => "Label in Dutch", "account_type" => "asset, liability, equity, revenue or expense",
      "normal_balance" => "debit or credit", "account_class" => "Class 1 to 7", "parent_code" => "Code of the parent account", "reconcilable" => "true when lines can be lettered",
      "active" => "false when archived", "currency" => "Currency of an account kept in a foreign currency"
    },
    "partners" => {
      "id" => "Identifier", "name" => "Name", "partner_type" => "customer, supplier or both", "vat_number" => "VAT number", "email" => "E-mail", "phone" => "Phone",
      "street" => "Street", "zip" => "Postal code", "city" => "City", "country" => "Country code", "iban" => "IBAN", "bic" => "BIC",
      "payment_terms_days" => "Payment terms in days", "external_ref" => "Reference in another system", "language" => "Language of the documents sent", "currency" => "Usual currency",
      "active" => "false when archived"
    },
    "journals" => {
      "code" => "Code", "label_fr" => "Label", "journal_type" => "sale, purchase, bank, cash or misc", "sequence_prefix" => "Prefix of the numbers given", "active" => "false when archived"
    },
    "vat_codes" => { "code" => "Code", "label" => "Label", "sens" => "sale or purchase", "nature" => "Nature of the transaction", "rate" => "Rate in percent" }
  }.freeze

  def self.markdown
    out = +"# Data exports\n\nGenerated from `Exports::Dictionary`; do not edit by hand (`bin/rails exports:docs`).\n\n"
    out << "Formats: CSV (UTF-8, comma), JSON (one document: `schema_version`, `dataset`, `generated_at`, `rows`) and XLSX (first sheet; at most #{Exports::Standard::XLSX_MAX_ROWS} rows, use the CSV beyond).\n\n"
    out << "Every CSV and XLSX row starts with `schema_version` (now #{Exports::Standard::SCHEMA_VERSION}); a change of column is a new version. Rows come ordered by identifier. "
    out << "Amounts are text with their decimals, never floats. The `entries` dataset can be limited to a period (`from`, `to`: entry date, bounds included).\n\n"
    COLUMNS.each do |dataset, columns|
      out << "## #{dataset}\n\n| Column | Meaning |\n| --- | --- |\n| schema_version | Version of this layout |\n"
      columns.each { |column, meaning| out << "| #{column} | #{meaning} |\n" }
      out << "\n"
    end
    out
  end
end
