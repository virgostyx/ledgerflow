# F06 step 1: works on a recorded inbound message: keeps its XML in the document store (F03, best effort: the message already holds it), then
# drafts the invoice. Never raises: a message that cannot be worked on becomes "needs_review" with the reasons, and can be worked on again
# once they are dealt with. A document that is not an invoice is kept, without an entry.
class Peppol::ProcessMessage
  KINDS = { "invoice" => :purchase_invoice, "credit_note" => :credit_note, "other" => :other }.freeze

  def self.call(message:)
    keep_in_document_store(message)
    if message.document_other?
      message.update!(status: message.xml.to_s.lstrip.start_with?("<") ? :processed : :needs_review,
                      note: [ message.note, "Document that is not an invoice: kept without an entry" ].compact.join(" · "),
                      problems: message.xml.to_s.lstrip.start_with?("<") ? [] : [ "The message is not an XML document" ])
    else
      draft_invoice(message)
    end
    message
  rescue StandardError => e
    message.update!(status: :needs_review, problems: [ "Unexpected error: #{e.message}" ])
    message
  end

  # Reads the document, checks it, and drafts the invoice when nothing is wrong. Every problem found is kept (not only the first), the message
  # can be worked on again once they are dealt with.
  def self.draft_invoice(message)
    canonical = Peppol::InvoiceMapper.call(message.xml)
    problems = Peppol::InvoiceChecks.call(canonical)
    rate = exchange_rate_for(canonical, problems)
    fiscal_year = Accounting::FiscalYear.current
    problems << "No open fiscal year to book the document in" unless fiscal_year
    return message.update!(status: :needs_review, problems: problems) if problems.any?

    result = Peppol::ReceiveInvoice.call(xml: message.xml, fiscal_year: fiscal_year, exchange_rate: rate)
    if result.failure?
      message.update!(status: :needs_review, problems: [ result.message ])
    else
      note = [ message.note, ("Invoice already received (same supplier and number): no second draft" if result[:duplicate]) ].compact.join(" · ").presence
      message.update!(status: :processed, invoice: result[:invoice], problems: [], note: note)
    end
  rescue Peppol::InvoiceMapper::Unreadable => e
    message.update!(status: :needs_review, problems: [ e.message ])
  end

  # EUR is 1; another currency takes the rate on file for the issue date, and never a guess: without one the message waits.
  def self.exchange_rate_for(canonical, problems)
    return BigDecimal("1") if canonical.currency == "EUR" || !Accounting::MoneyPresenter::SUPPORTED_CURRENCIES.include?(canonical.currency) || canonical.issue_date.nil?

    Accounting::ExchangeRate.rate_for(canonical.currency, canonical.issue_date).tap do |rate|
      problems << "No exchange rate for #{canonical.currency} on or before #{canonical.issue_date}: add it to the exchange rates, then work on the message again" unless rate
    end
  end

  def self.keep_in_document_store(message)
    return if message.document_id || message.xml.blank?

    result = Accounting::UploadDocument.call(io: StringIO.new(message.xml), filename: "peppol-#{message.message_id.tr('^A-Za-z0-9._-', '_')}.xml", user: nil,
                                             origin: :peppol, kind: KINDS.fetch(message.document_type), details: { "peppol_message_id" => message.message_id })
    document = result.success? ? result[:document] : result[:existing]
    if document
      message.update!(document: document)
    else
      message.update!(note: [ message.note, "Not kept in the document store: #{result.message}" ].compact.join(" · "))
    end
  end
  private_class_method :draft_invoice, :exchange_rate_for, :keep_in_document_store
end
