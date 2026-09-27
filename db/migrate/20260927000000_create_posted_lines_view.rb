class CreatePostedLinesView < ActiveRecord::Migration[8.1]
  # Reports read-only from this view rather than the raw tables (docs/dev/reports/spec.md §3),
  # so every report agrees on what "posted" means and on the entry-level fields it denormalizes.
  # `e.status = 1` is Accounting::JournalEntry's `posted` enum value — a view can't reference
  # the Ruby enum, so it's spelled out here; see spec/models/accounting/posted_line_spec.rb.
  def up
    execute <<~SQL
      CREATE VIEW posted_lines AS
      SELECT
        l.id                AS id,
        l.entity_id         AS entity_id,
        e.id                AS journal_entry_id,
        e.fiscal_year_id    AS fiscal_year_id,
        e.journal_id        AS journal_id,
        e.entry_date        AS entry_date,
        e.reference         AS reference,
        l.account_id        AS account_id,
        l.partner_id        AS partner_id,
        l.debit             AS debit,
        l.credit            AS credit,
        l.label             AS label,
        l.vat_code          AS vat_code,
        l.lettering_id      AS lettering_id,
        l.currency          AS currency,
        l.amount_currency   AS amount_currency
      FROM accounting_journal_entry_lines l
      JOIN accounting_journal_entries e ON e.id = l.journal_entry_id
      WHERE e.status = 1;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS posted_lines;"
  end
end
