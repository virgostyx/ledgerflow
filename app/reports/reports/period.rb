# A date range with a label and an optional comparative range, shared by every
# report (docs/dev/reports/spec.md §2.1). Lives at app/reports/reports/period.rb
# so the constant is Reports::Period, following this app's convention where an
# app/* root contributes no namespace of its own (see app/queries/accounting/*
# => Accounting::*) — app/reports/reports/* => Reports::*.
class Reports::Period
  attr_reader :start_date, :end_date, :label, :comparative

  def initialize(start_date:, end_date:, label: nil, comparative: nil)
    @start_date  = start_date
    @end_date    = end_date
    @label       = label
    @comparative = comparative
  end

  def self.for_fiscal_year(fiscal_year, comparative: nil)
    new(start_date: fiscal_year.start_date, end_date: fiscal_year.end_date,
        label: fiscal_year.year.to_s, comparative: comparative)
  end

  # The nth month by rank in the fiscal year (1..12), not by calendar month —
  # docs/dev/reports/spec.md §9: stays correct for a fiscal year that isn't Jan-Dec.
  def self.month(fiscal_year, n, comparative: nil)
    month_start = fiscal_year.start_date >> (n - 1)
    month_end   = [ (month_start >> 1) - 1, fiscal_year.end_date ].min
    new(start_date: month_start, end_date: month_end, label: "M#{n}", comparative: comparative)
  end

  def self.as_of(fiscal_year, date, comparative: nil)
    new(start_date: fiscal_year.start_date, end_date: date, label: date.to_s, comparative: comparative)
  end

  def comparative_period
    case comparative&.to_sym
    when :previous_year
      self.class.new(start_date: start_date.prev_year, end_date: end_date.prev_year)
    when :previous
      days = (end_date - start_date).to_i + 1
      self.class.new(start_date: start_date - days, end_date: start_date - 1)
    end
  end
end
