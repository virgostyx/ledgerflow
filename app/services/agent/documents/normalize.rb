# The value of a field in the canonical form F03 keeps it in (A09): two-decimal amounts, ISO dates, an IBAN without spaces, a VAT number without dots, the structured communication with its pluses.
# Nil when the value is not a value of that kind. Amounts, dates and other fields follow the rules of a person's confirmation (Accounting::ConfirmDocumentField). The identifiers with check digits keep
# their shape even when the digits are wrong: a misread number must reach the person marked invalid (Agent::Documents::Validation), not vanish as "not found".
module Agent::Documents::Normalize
  def self.value(field, raw)
    text = raw.to_s.strip
    return if text.empty?

    case field
    when "supplier_name" then text.first(120)
    when "iban" then (compact = Accounting::Iban.normalize(text)).match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/) ? compact : nil
    when "supplier_vat" then (compact = text.upcase.gsub(/[\s.]/, "")).match?(/\A[A-Z]{2}[A-Z0-9]{2,12}\z/) ? compact : nil
    when "structured_communication" then (digits = text.delete("^0-9")).length == 12 ? "+++#{digits[0, 3]}/#{digits[3, 4]}/#{digits[7, 5]}+++" : nil
    else Accounting::ConfirmDocumentField.clean(field, text) if Accounting::ConfirmDocumentField::FIELDS.include?(field)
    end
  rescue ArgumentError
    nil
  end
end
