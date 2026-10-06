# Finds in a text what identifies a person or a company, and checks it the way its issuer does, so that a number that only looks like one is left alone (A04): an IBAN (ISO 13616,
# modulo 97), a Belgian national number and a Belgian company or VAT number (modulo 97), a bank card number (Luhn).
module Agent::Identifiers
  IBAN = /\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,3})?\b/
  NATIONAL_NUMBER = /(?<![\d.])\d{2}[.\s]?\d{2}[.\s]?\d{2}[-\s]?\d{3}[.\s]?\d{2}(?![\d])/
  BELGIAN_VAT = /\bBE\s?[01]\d{3}[.\s]?\d{3}[.\s]?\d{3}\b/i
  COMPANY_NUMBER = /(?<![\d.])[01]\d{3}[.\s]\d{3}[.\s]\d{3}(?![\d])/
  FOREIGN_VAT = /\b(?:AT|BG|CY|CZ|DE|DK|EE|EL|ES|FI|FR|GB|HR|HU|IE|IT|LT|LU|LV|MT|NL|PL|PT|RO|SE|SI|SK)[A-Z0-9]{8,12}\b/
  CARD = /(?<![\d])(?:\d[ -]?){12,18}\d(?![\d])/

  # => [[matched text, normalized value]] of the valid ones, in order of appearance
  def self.ibans(text) = text.scan(IBAN).filter_map { |raw| [ raw, raw.delete(" ") ] if iban?(raw.delete(" ")) }
  def self.iban?(compact)
    return false unless compact.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{8,30}\z/)

    (compact[4..] + compact[0, 4]).chars.map { |char| char.match?(/\d/) ? char : (char.ord - 55).to_s }.join.to_i % 97 == 1
  end

  def self.national_number?(raw)
    digits = raw.gsub(/\D/, "")
    return false unless digits.length == 11

    base, check = digits[0, 9].to_i, digits[9, 2].to_i
    check == 97 - base % 97 || check == 97 - (2_000_000_000 + base) % 97
  end

  def self.belgian_company_number?(raw)
    digits = raw.gsub(/\D/, "")
    digits = digits[-10..] if digits.length > 10
    digits.length == 10 && digits[8, 2].to_i == 97 - digits[0, 8].to_i % 97
  end

  def self.card?(raw)
    digits = raw.gsub(/\D/, "")
    return false unless (13..19).cover?(digits.length)

    sum = digits.reverse.chars.each_with_index.sum { |char, index| (value = char.to_i * (index.odd? ? 2 : 1)) > 9 ? value - 9 : value }
    (sum % 10).zero?
  end
end
