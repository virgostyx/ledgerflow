require Rails.root.join("tools/ledger-verify/lib/ledger_verify/canonical")

# B03c: the content of a validated entry that is fingerprinted - what must never change - in canonical form (RFC 8785), and its fingerprint (SHA-256, in hexadecimal).
#
# In: the company, the journal, the fiscal year, the accounting date, the reference, the description, the link to the entry it reverses, the instant and place of validation, who
# validated, and every line (its order, account, partner, debit, credit, currency and amount in it, VAT code and amount, due date, label).
# Out, because they change legitimately after the validation: the status (an entry is reversed), the lettering and the residual of a line, its links to documents and invoices,
# the dunning and dispute marks.
#
# Amounts are decimal strings with the scale of their column; nothing goes through a float. `ledger-verify` writes the same object from `entries.ndjson`: a change to this
# format is a change of `VERSION`, never an edit in place.
module Ledger::EntryContent
  VERSION = 1

  # `lines`: the lines of the entry, when the caller already holds them (a package is made of hundreds of thousands of entries).
  def self.canonical(entry, lines: nil)
    lines ||= Accounting::JournalEntryLine.where(journal_entry_id: entry.id).order(:sort_order, :id).to_a
    {
      "v" => VERSION, "entity_id" => entry.entity_id, "journal_id" => entry.journal_id, "fiscal_year_id" => entry.fiscal_year_id, "entry_date" => entry.entry_date.iso8601,
      "reference" => entry.reference, "description" => entry.description, "reversal_of_id" => entry.reversal_of_id,
      "posted_at" => entry.posted_at.utc.iso8601(6), "posted_seq" => entry.posted_seq, "posted_by_id" => entry.posted_by_id,
      "lines" => lines.each_with_index.map { |line, index| line_content(line, index + 1) }
    }
  end

  # The content of many entries, their lines read in one query per batch: [[entry, content], ...]
  def self.canonical_many(entries)
    lines = Accounting::JournalEntryLine.where(journal_entry_id: entries.map(&:id)).order(:sort_order, :id).group_by(&:journal_entry_id)
    entries.map { |entry| [ entry, canonical(entry, lines: lines.fetch(entry.id, [])) ] }
  end

  def self.json(entry) = LedgerVerify::Canonical.generate(canonical(entry))

  def self.digest(entry) = Digest::SHA256.hexdigest(json(entry))

  def self.line_content(line, number)
    {
      "n" => number, "account_id" => line.account_id, "partner_id" => line.partner_id, "debit" => decimal(line.debit, 2), "credit" => decimal(line.credit, 2), "currency" => line.currency,
      "amount_currency" => line.amount_currency && decimal(line.amount_currency, 4), "exchange_rate" => line.exchange_rate && decimal(line.exchange_rate, 8), "vat_code" => line.vat_code,
      "vat_amount" => line.vat_amount && decimal(line.vat_amount, 2), "due_date" => line.due_date&.iso8601, "label" => line.label
    }
  end
  private_class_method :line_content

  # The value with exactly `scale` decimals, as text.
  def self.decimal(value, scale)
    whole, fraction = BigDecimal(value.to_s).round(scale).to_s("F").split(".")
    "#{whole}.#{fraction.to_s.ljust(scale, '0')}"
  end
  private_class_method :decimal
end
