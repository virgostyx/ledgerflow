# Account with a balance that no balance-sheet or income-statement rubric picks up (R07/R08).
class Accounting::Consistency::Checks::C13UnmappedAccount < Accounting::Consistency::Check
  self.check_id = "C13"
  self.severity = "warning"
  self.title = "Account not attached to a rubric"

  def call
    fiscal_years.flat_map do |fy|
      Accounting::AnnualAccounts.new(fiscal_year: fy).call.unmapped.map do |account|
        finding(subject: [ "Accounting::FiscalYear", fy.id ], message: "#{fy.year}: account #{account.code} (#{account.label}) is on no rubric", year: fy.year, code: account.code, balance: account.balance)
      end
    end
  end
end
