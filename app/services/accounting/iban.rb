# IBAN check (ISO 13616): shape, length for the SEPA countries, and the mod-97 check digits.
module Accounting::Iban
  LENGTHS = { "AT" => 20, "BE" => 16, "BG" => 22, "CH" => 21, "CY" => 28, "CZ" => 24, "DE" => 22, "DK" => 18, "EE" => 20, "ES" => 24,
              "FI" => 18, "FR" => 27, "GB" => 22, "GR" => 27, "HR" => 21, "HU" => 28, "IE" => 22, "IS" => 26, "IT" => 27, "LI" => 21,
              "LT" => 20, "LU" => 20, "LV" => 21, "MC" => 27, "MT" => 31, "NL" => 18, "NO" => 15, "PL" => 28, "PT" => 25, "RO" => 24,
              "SE" => 24, "SI" => 19, "SK" => 24, "SM" => 27 }.freeze

  def self.normalize(iban) = iban.to_s.gsub(/\s+/, "").upcase

  def self.valid?(iban)
    number = normalize(iban)
    return false unless number.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/)
    return false if LENGTHS[number[0, 2]] && number.length != LENGTHS[number[0, 2]]

    digits = (number[4..] + number[0, 4]).chars.map { |char| char.match?(/\d/) ? char : (char.ord - 55).to_s }.join
    digits.to_i % 97 == 1
  end
end
