# Invariants that can be checked at runtime on an open fiscal year: I2 (Σ debit = Σ credit), I6 (balance
# sheet balanced), I7 (VAT return = ledger, per declaration) and I11 (regularizations = accounts 490-493).
# I10 is check C16; I1 is C01; I3-I5, I8 and I9 are not replayed here.
class Accounting::Consistency::Checks::C11Invariants < Accounting::Consistency::Check
  self.check_id = "C11"
  self.severity = "blocking"
  self.title = "Invariant not respected"

  def call
    fiscal_years.flat_map do |fy|
      i2(fy) + i6(fy) + i7(fy) + i11(fy)
    end
  end

  private

  def i2(fy)
    debit, credit = Accounting::PostedLine.where(fiscal_year_id: fy.id).pick(Arel.sql("COALESCE(SUM(debit), 0)"), Arel.sql("COALESCE(SUM(credit), 0)"))
    debit == credit ? [] : [ finding(subject: fy, message: "I2 — #{fy.year}: total debit #{debit} ≠ total credit #{credit}", invariant: "I2", debit: debit, credit: credit) ]
  end

  def i6(fy)
    report = Accounting::AnnualAccounts.new(fiscal_year: fy).call
    report.balanced? ? [] : [ finding(subject: fy, message: "I6 — #{fy.year}: assets − liabilities = #{report.difference}", invariant: "I6", difference: report.difference) ]
  end

  def i7(fy)
    Accounting::VatDeclaration.where(fiscal_year_id: fy.id).filter_map do |declaration|
      residual = Accounting::VatConsistencyQuery.new(declaration: declaration).call.residual
      next if residual.zero?

      finding(subject: declaration, message: "I7 — VAT return #{declaration.period_start}–#{declaration.period_end}: #{residual} unexplained", invariant: "I7", residual: residual)
    end
  end

  def i11(fy)
    Accounting::AccrualsReportQuery.new(fiscal_year: fy).call.checks.reject { |c| c.difference.zero? }.map do |c|
      finding(subject: fy, message: "I11 — #{fy.year}: #{c.label}, difference #{c.difference}", invariant: "I11", label: c.label, difference: c.difference)
    end
  end
end
