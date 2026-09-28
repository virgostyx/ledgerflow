# Entry dated outside its own fiscal year.
class Accounting::Consistency::Checks::C02EntryOutsideFiscalYear < Accounting::Consistency::Check
  self.check_id = "C02"
  self.severity = "blocking"
  self.title = "Entry dated outside its fiscal year"

  def call
    Accounting::JournalEntry.joins(:fiscal_year)
      .where("accounting_journal_entries.entry_date NOT BETWEEN accounting_fiscal_years.start_date AND accounting_fiscal_years.end_date")
      .pluck(:id, :reference, :entry_date, Arel.sql("accounting_fiscal_years.year")).map do |id, reference, date, year|
      finding(subject: [ "Accounting::JournalEntry", id ], message: "Entry #{reference || "##{id}"} is dated #{date}, outside fiscal year #{year}", date: date.to_s, year: year)
    end
  end
end
