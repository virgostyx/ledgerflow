# Data exports

Generated from `Exports::Dictionary`; do not edit by hand (`bin/rails exports:docs`).

Formats: CSV (UTF-8, comma), JSON (one document: `schema_version`, `dataset`, `generated_at`, `rows`) and XLSX (first sheet; at most 100000 rows, use the CSV beyond).

Every CSV and XLSX row starts with `schema_version` (now 1); a change of column is a new version. Rows come ordered by identifier. Amounts are text with their decimals, never floats. The `entries` dataset can be limited to a period (`from`, `to`: entry date, bounds included).

## entries

| Column | Meaning |
| --- | --- |
| schema_version | Version of this layout |
| entry_id | Identifier of the entry |
| reference | Number given when the entry was validated (empty for a draft) |
| entry_date | Date of the entry, YYYY-MM-DD |
| journal | Code of the journal |
| status | draft, posted or reversed |
| fiscal_year | Year of the fiscal year |
| description | Description of the entry |
| external_id | Key of the piece in the file it was imported from (F13a) |
| line_id | Identifier of the line |
| account | Code of the account |
| partner | Name of the partner on the line |
| partner_vat | VAT number of that partner |
| label | Label of the line |
| debit | Debit in EUR, two decimals |
| credit | Credit in EUR, two decimals |
| currency | Currency of the line (EUR unless the line is in a foreign currency) |
| amount_currency | Amount in that currency, signed (debit positive); empty in EUR |
| exchange_rate | Units of that currency for 1 EUR; empty in EUR |

## accounts

| Column | Meaning |
| --- | --- |
| schema_version | Version of this layout |
| code | Code of the account |
| label_fr | Label in French |
| label_nl | Label in Dutch |
| account_type | asset, liability, equity, revenue or expense |
| normal_balance | debit or credit |
| account_class | Class 1 to 7 |
| parent_code | Code of the parent account |
| reconcilable | true when lines can be lettered |
| active | false when archived |
| currency | Currency of an account kept in a foreign currency |

## partners

| Column | Meaning |
| --- | --- |
| schema_version | Version of this layout |
| id | Identifier |
| name | Name |
| partner_type | customer, supplier or both |
| vat_number | VAT number |
| email | E-mail |
| phone | Phone |
| street | Street |
| zip | Postal code |
| city | City |
| country | Country code |
| iban | IBAN |
| bic | BIC |
| payment_terms_days | Payment terms in days |
| external_ref | Reference in another system |
| language | Language of the documents sent |
| currency | Usual currency |
| active | false when archived |

## journals

| Column | Meaning |
| --- | --- |
| schema_version | Version of this layout |
| code | Code |
| label_fr | Label |
| journal_type | sale, purchase, bank, cash or misc |
| sequence_prefix | Prefix of the numbers given |
| active | false when archived |

## vat_codes

| Column | Meaning |
| --- | --- |
| schema_version | Version of this layout |
| code | Code |
| label | Label |
| sens | sale or purchase |
| nature | Nature of the transaction |
| rate | Rate in percent |

