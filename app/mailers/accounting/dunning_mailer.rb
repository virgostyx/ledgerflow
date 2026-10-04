# The e-mail of a reminder (F09): the text of the item as written, with the statement of account and the original invoices attached.
# The sending address is the application's (SPF and DKIM are the domain's, see QUESTIONS.md); the entity gives the name and the reply address.
class Accounting::DunningMailer < ApplicationMailer
  PDF = "application/pdf".freeze

  def reminder(item)
    entity = item.entity
    policy = Accounting::DunningPolicy.for(entity)

    ActsAsTenant.with_tenant(entity) do # the PDFs read the issuer and bank account of the tenant; a job runs without one
      attachments["statement-of-account.pdf"] = { mime_type: PDF, content: Accounting::DunningPdf.new(item, letter: false).render }
      original_documents(item).each { |name, file| attachments[name] = { mime_type: file.content_type, content: file.download } }
    end

    mail(to: item.recipient, subject: item.subject, body: item.body, reply_to: policy.reply_to.presence,
         from: email_address_with_name(Accounting::InvoiceMailer::FROM_ADDRESS, policy.from_name.presence || entity.legal_name))
  end

  private

  # The documents of F03 linked to the entries or invoices that the reminder asks for; for an invoice issued here with none, its own PDF.
  # ponytail: no ceiling on the size of the message, add one if a customer has dozens of invoices.
  def original_documents(item)
    lines   = item.item_lines.includes(line: [ :journal_entry, :invoice ]).map(&:line)
    targets = lines.flat_map { |l| [ [ "Accounting::JournalEntry", l.journal_entry_id ], ([ "Accounting::Invoice", l.invoice_id ] if l.invoice_id) ] }.compact.uniq
    return {} if targets.empty?

    documents = Accounting::Document.joins(:links).where(links_condition(targets)).distinct.includes(file_attachment: :blob).to_a
    names = documents.to_h { |d| [ d.name, d.file ] }
    lines.filter_map(&:invoice).uniq.each do |invoice|
      next if documents.any? { |d| d.links.any? { |l| l.target_type == "Accounting::Invoice" && l.target_id == invoice.id } }

      names["#{invoice.invoice_number.tr('/', '-')}.pdf"] = StringIO.new(Accounting::InvoicePdf.new(invoice).render).then { |io| generated(io) }
    end
    names
  end

  def links_condition(targets)
    targets.map { |type, id| Accounting::DocumentLink.sanitize_sql([ "(accounting_document_links.target_type = ? AND accounting_document_links.target_id = ?)", type, id ]) }.join(" OR ")
  end

  Generated = Struct.new(:content_type, :bytes) { def download = bytes }
  def generated(io) = Generated.new(PDF, io.string)
end
