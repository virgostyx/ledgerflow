# Booked regularization with no reversal generated (R17).
class Accounting::Consistency::Checks::C17AccrualWithoutReversal < Accounting::Consistency::Check
  self.check_id = "C17"
  self.severity = "warning"
  self.title = "Regularization without a reversal"

  def call
    fiscal_years.flat_map do |fy|
      Accounting::AccrualsReportQuery.new(fiscal_year: fy).call.rows.select(&:missing_reversal).map do |row|
        finding(subject: row.accrual, message: "#{fy.year}: “#{row.accrual.description}” is booked but has no reversal", year: fy.year)
      end
    end
  end
end
