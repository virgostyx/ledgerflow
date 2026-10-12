# What is left to pay on purchase invoices (B01b): the open residual of the line of each invoice's entry on the suppliers' account, added up by the database (the line is
# found through the entry, as the rest of the application finds it). Positive for an invoice, negative for a credit note. => { invoice_id => BigDecimal }
module Payments::OpenAmounts
  def self.rests(invoices, as_of: Date.current)
    by_entry = Accounting::OpenLineSql.open_scope(kind: :supplier, as_of: as_of).where(journal_entry_id: invoices.filter_map(&:journal_entry_id))
                                      .group("accounting_journal_entry_lines.journal_entry_id").sum(Arel.sql("(#{Accounting::OpenLineSql.residual(kind: :supplier, as_of: as_of)})"))
    invoices.to_h { |invoice| [ invoice.id, by_entry.fetch(invoice.journal_entry_id, BigDecimal("0")) ] }
  end
end
