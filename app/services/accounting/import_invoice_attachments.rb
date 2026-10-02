# One-off, idempotent: the UBL and PDF already kept on invoices (Peppol, BudgetFlow) join the document store (F03),
# origin Peppol, linked to their invoice. A file the store already holds (same SHA-256) is only linked, never stored
# twice. Runs for the current entity. => { imported: n, refused: ["name: reason"] }
class Accounting::ImportInvoiceAttachments
  ATTACHMENTS = %i[ubl_document pdf_document].freeze

  def self.call
    result = { imported: 0, refused: [] }
    Accounting::Invoice.find_each do |invoice|
      ATTACHMENTS.each do |name|
        next unless invoice.public_send(name).attached?

        import(invoice, invoice.public_send(name), result)
      end
    end
    result
  end

  def self.import(invoice, attachment, result)
    bytes = attachment.download
    filename = attachment.filename.to_s
    document = Accounting::Document.find_by(sha256: Digest::SHA256.hexdigest(bytes))
    if document
      return if document.links.exists?(target: invoice)
    else
      upload = Accounting::UploadDocument.call(io: StringIO.new(bytes), filename: filename, user: nil, origin: :peppol,
                                               kind: invoice.supplier? ? :purchase_invoice : :sales_invoice)
      return result[:refused] << "#{filename}: #{upload.message}" if upload.failure?

      document = upload[:document]
    end
    link = Accounting::LinkDocument.call(document: document, target: invoice, user: nil)
    link.success? ? result[:imported] += 1 : result[:refused] << "#{filename}: #{link.message}"
  end
  private_class_method :import
end
