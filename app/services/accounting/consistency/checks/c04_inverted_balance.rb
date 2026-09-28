# Customer (40), supplier (44) or bank (55) account whose balance has the wrong sign, beyond a 1 cent tolerance.
class Accounting::Consistency::Checks::C04InvertedBalance < Accounting::Consistency::Check
  self.check_id = "C04"
  self.severity = "warning"
  self.title = "Account with an inverted balance"
  TOLERANCE = BigDecimal("0.01")

  def call
    fiscal_years.flat_map do |fiscal_year|
      Accounting::PostedLine.joins(:account).where(fiscal_year_id: fiscal_year.id)
        .where("accounting_accounts.code LIKE '40%' OR accounting_accounts.code LIKE '44%' OR accounting_accounts.code LIKE '55%'")
        .group("accounting_accounts.id", "accounting_accounts.code")
        .pluck(Arel.sql("accounting_accounts.id"), Arel.sql("accounting_accounts.code"), Arel.sql("SUM(posted_lines.debit - posted_lines.credit)")).filter_map do |id, code, net|
        net = BigDecimal(net.to_s)
        wrong = code.start_with?("44") ? net > TOLERANCE : net < -TOLERANCE
        next unless wrong

        finding(subject: [ "Accounting::Account", id ], message: "Account #{code} has #{net.positive? ? 'a debit' : 'a credit'} balance of #{net.abs} in #{fiscal_year.year}",
                year: fiscal_year.year, net: net)
      end
    end
  end
end
