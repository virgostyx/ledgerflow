# The few IBAN and reference checks the statements need.
module Banking::Iban
  # The IBAN of a Belgian account number (12 digits, the last 2 being the check: the first 10 digits modulo 97, 97 for 0), or nil.
  def self.from_belgian_bban(bban)
    bban = bban.to_s
    return unless bban.match?(/\A\d{12}\z/)

    expected = bban[0, 10].to_i % 97
    return unless bban[10, 2].to_i == (expected.zero? ? 97 : expected)

    "BE#{format('%02d', 98 - "#{bban}111400".to_i % 97)}#{bban}"
  end

  # ISO 13616: rearranged, letters as numbers, modulo 97 = 1.
  def self.valid?(iban)
    iban = iban.to_s.delete(" ").upcase
    iban.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{10,30}\z/) && numeric("#{iban[4..]}#{iban[0, 4]}") % 97 == 1
  end

  # ISO 11649 creditor reference: "RF", 2 check digits, up to 21 characters.
  def self.valid_creditor_reference?(reference)
    reference = reference.to_s.delete(" ").upcase
    reference.match?(/\ARF\d{2}[A-Z0-9]{1,21}\z/) && numeric("#{reference[4..]}#{reference[0, 4]}") % 97 == 1
  end

  def self.numeric(text) = text.gsub(/[A-Z]/) { |c| (c.ord - 55).to_s }.to_i
  private_class_method :numeric
end
