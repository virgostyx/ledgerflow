# Belgian structured communication (+++123/4567/89012+++): 10-digit base + 2-digit check (base mod 97, 97 if 0).
# For customer invoices the base is the invoice id, so no extra column is needed.
module Accounting::StructuredCommunication
  PATTERN = %r{\+{3}(\d{3})/(\d{4})/(\d{5})\+{3}|\b(\d{12})\b}

  def self.valid?(digits)
    digits.to_s.match?(/\A\d{12}\z/) && digits[10, 2].to_i == check_for(digits[0, 10].to_i)
  end

  def self.extract(text)
    return unless (m = PATTERN.match(text.to_s))

    digits = m[4] || (m[1] + m[2] + m[3])
    digits if valid?(digits)
  end

  def self.for_id(id)
    base = Kernel.format("%010d", id)
    base + Kernel.format("%02d", check_for(base.to_i))
  end

  def self.id_from(digits)
    digits[0, 10].to_i
  end

  def self.display(digits)
    "+++#{digits[0, 3]}/#{digits[3, 4]}/#{digits[7, 5]}+++"
  end

  def self.check_for(base)
    (base % 97).then { |r| r.zero? ? 97 : r }
  end
  private_class_method :check_for
end
