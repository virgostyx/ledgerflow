# F06 step 3: who sent the invoice. The partner is looked up by VAT number, then by enterprise number (BCE: the Belgian VAT number is
# "BE" + that number), then by IBAN, and the first level that finds exactly one partner wins. Several partners at one level is not a guess to
# make: it is a problem, and the document waits. Nobody found: nil, and Peppol::ReceiveInvoice creates the supplier as "to validate".
# => Result(partner, by, problem)
class Peppol::SupplierMatch
  Result = Struct.new(:partner, :by, :problem, keyword_init: true)

  def self.find(supplier)
    candidates(supplier).each do |by, scope|
      found = scope.limit(2).to_a
      return Result.new(partner: found.first, by: by) if found.one?
      return Result.new(by: by, problem: "Several partners have the #{by.to_s.tr('_', ' ')} of the supplier #{supplier.name.inspect}: pick the right one, then work on the message again") if found.size > 1
    end
    Result.new
  end

  def self.candidates(supplier)
    list = []
    list << [ :vat_number, Accounting::Partner.where(vat_number: supplier.vat) ] if supplier.vat.present?
    bce = enterprise_number(supplier)
    list << [ :enterprise_number, Accounting::Partner.where(vat_number: "BE#{bce}") ] if bce
    iban = Accounting::Iban.normalize(supplier.iban)
    list << [ :iban, Accounting::Partner.where("upper(replace(iban, ' ', '')) = ?", iban) ] if iban.present? && Accounting::Iban.valid?(iban)
    list
  end

  # The Belgian enterprise number (10 digits): a company identifier of scheme 0208, else the digits of the endpoint of that scheme.
  def self.enterprise_number(supplier)
    from_company = supplier.company_id.to_s.delete("^0-9") if supplier.company_scheme == "0208"
    from_endpoint = supplier.endpoint.to_s.delete_prefix("0208:").delete("^0-9") if supplier.endpoint.to_s.start_with?("0208:")
    [ from_company, from_endpoint ].compact.find { |digits| digits.size == 10 }
  end
  private_class_method :candidates, :enterprise_number
end
