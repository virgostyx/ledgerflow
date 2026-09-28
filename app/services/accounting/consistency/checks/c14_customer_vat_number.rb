# Domestic customer above the annual-listing threshold without a valid VAT number (R10).
class Accounting::Consistency::Checks::C14CustomerVatNumber < Accounting::Consistency::Check
  self.check_id = "C14"
  self.severity = "warning"
  self.title = "Customer without a valid VAT number"

  def call
    fiscal_years.flat_map do |fy|
      Accounting::AnnualCustomerListingQuery.new(fiscal_year: fy).call.rows.select { |r| r.anomalies.any? }.map do |row|
        finding(subject: [ "Accounting::Partner", row.partner_id ], message: "#{fy.year}: #{row.partner_name} (#{row.amount_excl_vat} excl. VAT) — #{row.anomalies.join(', ').tr('_', ' ')}",
                year: fy.year, amount: row.amount_excl_vat, anomalies: row.anomalies.map(&:to_s))
      end
    end
  end
end
