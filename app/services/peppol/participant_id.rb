# A Peppol participant identifier: "<scheme>:<value>", e.g. 0208:0123456789 (0208 = Belgian enterprise number).
module Peppol::ParticipantId
  FORMAT = /\A\d{4}:[A-Za-z0-9][A-Za-z0-9._-]*\z/
  BELGIAN_SCHEME = "0208".freeze

  def self.valid?(id)
    return false unless id.to_s.match?(FORMAT)

    scheme, value = id.split(":", 2)
    scheme != BELGIAN_SCHEME || value.match?(/\A\d{10}\z/)
  end

  # 0208:<enterprise number> for a Belgian VAT number (BE0123456789); nil for anything else: nothing is guessed.
  def self.from_belgian_vat(vat_number)
    digits = vat_number.to_s[/\ABE(\d{10})\z/, 1]
    "#{BELGIAN_SCHEME}:#{digits}" if digits
  end
end
