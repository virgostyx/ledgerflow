# Step 5 of the closing (F10): VAT. Each VAT period of the year has its declaration submitted and its dates locked (R09). An entity under the franchise has
# none to file.
class Closing::Steps::Vat < Closing::Step
  self.position = 5
  self.code     = "vat"
  self.title    = "VAT"
  self.kind     = :check
  self.blocking = true

  def evaluate
    return ok("franchise" => true) if run.entity.franchise?

    periods = vat_periods.map { |from, to| read(from, to) }
    details = { "periods" => periods }
    periods.all? { |p| p["submitted"] && p["locked"] } ? ok(details) : blocked(details)
  end

  private

  # [[start, end], ...]: the months or quarters of the year, from its first day.
  def vat_periods
    step = run.entity.vat_filing_frequency == "monthly" ? 1 : 3
    periods = []
    from = fiscal_year.start_date
    while from <= year_end
      periods << [ from, [ (from >> step) - 1, year_end ].min ]
      from >>= step
    end
    periods
  end

  def read(from, to)
    submitted = Accounting::VatDeclaration.where(fiscal_year: fiscal_year, period_start: from, status: %i[submitted accepted]).exists?
    locked = Accounting::PeriodLock.in_force.where(kind: :vat).where("starts_on <= ? AND ends_on >= ?", from, to).exists?
    { "from" => from.to_s, "to" => to.to_s, "submitted" => submitted, "locked" => locked }
  end
end
