# Invoice booked long after (or before) its document date.
class Accounting::Consistency::Checks::C12DateGap < Accounting::Consistency::Check
  self.check_id = "C12"
  self.severity = "info"
  self.title = "Large gap between document date and accounting date"
  MAX_DAYS = 92 # about N = 3 months

  def call
    Accounting::Invoice.joins(:journal_entry)
      .where("ABS(accounting_journal_entries.entry_date - accounting_invoices.invoice_date) > ?", MAX_DAYS)
      .pluck(:id, :invoice_number, :invoice_date, Arel.sql("accounting_journal_entries.entry_date")).map do |id, number, doc_date, entry_date|
      finding(subject: [ "Accounting::Invoice", id ], message: "Invoice #{number || "##{id}"}: document #{doc_date}, booked #{entry_date}", document: doc_date.to_s, booked: entry_date.to_s)
    end
  end
end
