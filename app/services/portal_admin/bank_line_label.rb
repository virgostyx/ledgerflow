# B02b: what a client may read of a bank line's wording: the counterparty's name, or the description without any IBAN and without long numbers (references, card numbers). The counterparty's own
# IBAN is removed wherever it is written (with or without spaces); any other IBAN-like run is removed when its groups carry digits.
class PortalAdmin::BankLineLabel
  IBAN = /\b[A-Z]{2}\d{2}(?: ?(?=[A-Z0-9]*\d)[A-Z0-9]{4}){2,7}(?: ?(?=[A-Z0-9]*\d)[A-Z0-9]{1,3})?\b/
  LONG_NUMBER = /\b\d{9,}\b/

  def self.call(transaction)
    return transaction.counterparty_name.squish.first(80) if transaction.counterparty_name.present?

    text = transaction.description.to_s
    if (iban = transaction.counterparty_iban.to_s.delete(" ").presence)
      text = text.gsub(Regexp.new(iban.chars.map { |c| Regexp.escape(c) }.join(" ?"), Regexp::IGNORECASE), "")
    end
    text.gsub(IBAN, "").gsub(LONG_NUMBER, "").squish.first(80)
  end
end
