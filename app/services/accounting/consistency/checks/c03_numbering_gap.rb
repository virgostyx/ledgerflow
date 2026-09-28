# Missing numbers in a journal's sequence for an open fiscal year (R03).
class Accounting::Consistency::Checks::C03NumberingGap < Accounting::Consistency::Check
  self.check_id = "C03"
  self.severity = "warning"
  self.title = "Gap in journal numbering"

  def call
    Accounting::Journal.find_each.flat_map do |journal|
      fiscal_years.map do |fiscal_year|
        gaps = Accounting::JournalNumberingGaps.new(journal: journal, fiscal_year: fiscal_year).call
        next if gaps.empty?

        finding(subject: journal, message: "Journal #{journal.code}, #{fiscal_year.year}: missing numbers #{gaps.first(10).join(', ')}#{'…' if gaps.size > 10}",
                year: fiscal_year.year, gaps: gaps)
      end.compact
    end
  end
end
