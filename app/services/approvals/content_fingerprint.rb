# The fingerprint of what an approval is about (B01a §4.5): SHA-256 of a canonical form of the significant fields of a
# purchase invoice. Free labels (descriptions, notes), the number given at posting and the order the lines were typed in
# do not count; the supplier, the amounts, the accounts, the due date, the currency and the supporting documents do.
# ponytail: the IBAN written on the invoice counts too once it is stored (audit §7.8); until then it is not part of the content.
class Approvals::ContentFingerprint
  def self.call(invoice)
    Digest::SHA256.hexdigest(JSON.generate(canonical(invoice)))
  end

  def self.canonical(invoice)
    {
      partner_id: invoice.partner_id,
      document_type: invoice.document_type,
      currency: invoice.currency,
      exchange_rate: decimal(invoice.exchange_rate),
      due_date: invoice.due_date&.iso8601,
      lines: invoice.lines.reload.map { |line| line_content(line) }.sort,
      documents: Accounting::DocumentLink.where(target: invoice).joins(:document).pluck("accounting_documents.sha256").sort
    }
  end

  def self.line_content(line)
    [ line.account_id, decimal(line.quantity), decimal(line.unit_price), decimal(line.vat_rate), line.vat_code.to_s ]
  end

  def self.decimal(value) = value.to_d.to_s("F")
  private_class_method :canonical, :line_content, :decimal
end
