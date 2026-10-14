class Accounting::VatGridQuery
  # known_at (B03a): the grids as they were known at that instant (a Time or an Accounting::KnownAt). An entry reversed since still counts until its reversal was validated
  # (a reversal does not copy the VAT codes, so today only the entries still `posted` count).
  def self.call(fiscal_year_id:, period_start:, period_end:, known_at: nil)
    known = Accounting::KnownAt.wrap(known_at).ensure_viewable!
    known.cache("vat_grid", { year: fiscal_year_id, from: period_start, to: period_end }) { grids(fiscal_year_id, period_start, period_end, known) }
  end

  def self.grids(fiscal_year_id, period_start, period_end, known)
    lines = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(accounting_journal_entries: { fiscal_year_id: fiscal_year_id })
      .where("accounting_journal_entries.entry_date BETWEEN ? AND ?", period_start, period_end)
    lines = in_force(lines, known)

    rows = lines.where.not(vat_code: nil).group(:vat_code).sum(:vat_amount)
    add_reverse_charge_bases(lines, rows)
    add_purchase_credit_note_bases(lines, rows)

    rows.sort.to_h { |code, total| [ format("%02d", code), total ] }
  end

  def self.in_force(lines, known)
    return lines.where(accounting_journal_entries: { status: Accounting::JournalEntry.statuses[:posted] }) if known.current?

    known.restrict(lines).where(accounting_journal_entries: { status: Accounting::JournalEntry.ledger_status_values })
         .where("NOT EXISTS (SELECT 1 FROM accounting_journal_entries r WHERE r.reversal_of_id = accounting_journal_entries.id AND r.posted_seq <= ?)", known.seq)
  end
  private_class_method :in_force, :grids

  # Reverse-charge purchases (86-88) also count in the base grid of their expense account (81-83).
  def self.add_reverse_charge_bases(lines, rows)
    lines.where(vat_code: Accounting::VatGrid.reverse_charge_purchase_grids).joins(:account)
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
    non_deductible = Accounting::AccountCodes::VAT_NON_DEDUCTIBLE # its VAT share is not part of the credit note amount
    negatives = lines.joins(:account).where.not(accounting_accounts: { code: non_deductible })
                     .where("accounting_journal_entry_lines.vat_amount < 0").group(:vat_code).sum(:vat_amount)
    Accounting::VatGrid.credit_note_recap_grids.each do |grid, codes|
      total = -negatives.values_at(*codes).compact.sum
      rows[grid] = total if total.positive?
    end
  end
  private_class_method :add_purchase_credit_note_bases
end
