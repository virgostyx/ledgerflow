# The days a SEPA credit transfer settles (B01b): weekdays, except the closing days of TARGET (1 January, Good Friday, Easter Monday, 1 May, 25 and 26 December).
# A bank may close more days: its profile lists them (`options["closed_days"]`, ISO dates). Easter is computed (the Gregorian algorithm), not read from a table.
module Payments::SettlementCalendar
  def self.open?(date, extra_closed: [])
    return false if date.saturday? || date.sunday?
    return false if target_holidays(date.year).include?(date)

    !Array(extra_closed).map(&:to_s).include?(date.iso8601)
  end

  # The first day on or after `date` that settles.
  def self.next_open(date, extra_closed: [])
    date += 1 until open?(date, extra_closed: extra_closed)
    date
  end

  def self.target_holidays(year)
    easter = easter_sunday(year)
    [ Date.new(year, 1, 1), easter - 2, easter + 1, Date.new(year, 5, 1), Date.new(year, 12, 25), Date.new(year, 12, 26) ]
  end

  # Easter Sunday of the Gregorian calendar (the "anonymous" algorithm of Meeus, Jones and Butcher).
  def self.easter_sunday(year)
    a = year % 19
    b, c = year.divmod(100)
    d, e = b.divmod(4)
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c.divmod(4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month, day = (h + l - 7 * m + 114).divmod(31)
    Date.new(year, month, day + 1)
  end
  private_class_method :target_holidays, :easter_sunday
end
