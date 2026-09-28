# Belgian VAT number check (docs/dev/reports/spec.md §10, R10): BE + 0/1 + 8 digits + 2 check
# digits, where check = 97 - (first eight digits mod 97).
module Accounting::BelgianVatNumber
  SHAPE = /\ABE([01]\d{7})(\d{2})\z/

  def self.valid?(number)
    match = SHAPE.match(number.to_s.upcase.gsub(/[\s.]/, ""))
    return false unless match

    97 - (match[1].to_i % 97) == match[2].to_i
  end
end
