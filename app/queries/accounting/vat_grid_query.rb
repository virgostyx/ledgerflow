class Accounting::VatGridQuery
  def self.call(fiscal_year_id:, period_start:, period_end:)
    lines = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: fiscal_year_id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where("accounting_journal_entries.entry_date BETWEEN ? AND ?", period_start, period_end)

    rows = lines.where.not(vat_code: nil).group(:vat_code).sum(:vat_amount)
    add_reverse_charge_bases(lines, rows)
    add_purchase_credit_note_bases(lines, rows)

    rows.sort.to_h { |code, total| [ format("%02d", code), total ] }
  end

  # Reverse-charge purchases (86-88) also count in the base grid of their expense account (81-83).
  def self.add_reverse_charge_bases(lines, rows)
    lines.where(vat_code: Accounting::VatGrid::REVERSE_CHARGE_PURCHASE_GRIDS).joins(:account)
         .group("accounting_accounts.code").sum(:vat_amount).each do |account_code, total|
      grid = Accounting::VatGrid.purchase_base_grid(account_code)
      rows[grid] = rows.fetch(grid, 0) + total if grid
    end
  end
  private_class_method :add_reverse_charge_bases

  # Credit notes received (negative purchase bases) are also shown apart: 84 for grids 86/88,
  # 85 for grid 87 and for domestic purchases (81-83). Computed before the 81-83 derivation of
  # reverse-charge lines, which are already counted through their own grid.
  def self.add_purchase_credit_note_bases(lines, rows)
    negatives = lines.where("accounting_journal_entry_lines.vat_amount < 0").group(:vat_code).sum(:vat_amount)
    { 84 => [ 86, 88 ], 85 => [ 81, 82, 83, 87 ] }.each do |grid, codes|
      total = -negatives.values_at(*codes).compact.sum
      rows[grid] = total if total.positive?
    end
  end
  private_class_method :add_purchase_credit_note_bases
end
