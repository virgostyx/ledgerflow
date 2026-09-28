# Fixed-asset register vs accounts 21–28, accumulated depreciation and the year's charge (I10, R16).
class Accounting::Consistency::Checks::C16FixedAssetRegister < Accounting::Consistency::Check
  self.check_id = "C16"
  self.severity = "blocking"
  self.title = "Fixed-asset register differs from the ledger"

  def call
    fiscal_years.flat_map do |fy|
      Accounting::FixedAssetMovementsQuery.new(fiscal_year: fy).call.checks.reject { |c| c.difference.zero? }.map do |c|
        finding(subject: fy, message: "#{fy.year}: #{c.label} — register #{c.register}, ledger #{c.ledger}", label: c.label, register: c.register, ledger: c.ledger)
      end
    end
  end
end
