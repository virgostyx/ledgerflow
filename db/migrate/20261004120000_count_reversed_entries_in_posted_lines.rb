# F07: an entry that was reversed stays a validated entry of the ledger, as does its reversal: the two net to zero. The view that feeds the
# reports left the reversed original out and kept the reversal, which distorted every balance (a reversed entry of 100 showed 100 on
# each side). Status 1 is posted, 2 is reversed (Accounting::JournalEntry::LEDGER_STATUSES).
class CountReversedEntriesInPostedLines < ActiveRecord::Migration[8.1]
  def up
    replace_view "e.status IN (1, 2)"
  end

  def down
    replace_view "e.status = 1"
  end

  private

  def replace_view(condition)
    execute <<~SQL
      CREATE OR REPLACE VIEW posted_lines AS
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
      WHERE #{condition};
    SQL
  end
end
