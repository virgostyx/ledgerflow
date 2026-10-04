# "Create the entry" from a document (F03): a prefilled DRAFT supplier invoice, linked to the document. The header comes
# from what a person confirmed, else from what was proposed (the audit says which); NO line is invented: the accountant
# adds the lines with their accounts. Nothing is posted. A probable duplicate (same supplier, same invoice number, not
# cancelled) is refused unless a reason is given, which is audited.
class Accounting::CreateInvoiceFromDocument
  def self.call(document:, partner:, user:, override_reason: nil) = new(document, partner, user, override_reason).call

  def initialize(document, partner, user, override_reason)
    @document = document
    @partner = partner
    @user = user
    @override_reason = override_reason.to_s.strip.presence
    @used = {}
  end

  def call
    return refuse(:no_supplier) unless supplier?
    return refuse(:archived) if @document.archived?

    date = date_of("invoice_date") || Date.current
    fiscal_year = Accounting::FiscalYear.where(status: %i[open pre_closing]).find_by("start_date <= :d AND end_date >= :d", d: date)
    return refuse(:no_fiscal_year, date: date) unless fiscal_year

    reference = value("invoice_number")
    duplicate = probable_duplicate(reference)
    return refuse(:duplicate_invoice, existing: duplicate, number: duplicate.invoice_number || duplicate.supplier_reference) if duplicate && @override_reason.nil?

    invoice = nil
    ApplicationRecord.transaction do
      invoice = Accounting::Invoice.create!(attributes(date, fiscal_year, reference))
      linked = Accounting::LinkDocument.call(document: @document, target: invoice, user: @user)
      raise ActiveRecord::Rollback, linked.message if linked.failure?

      classify
      audit(invoice, duplicate)
    end
    LightService::Context.make(invoice: invoice)
  end

  private

  def supplier?
    @partner.is_a?(Accounting::Partner) && @partner.entity_id == @document.entity_id && (@partner.supplier? || @partner.both?)
  end

  def attributes(date, fiscal_year, reference)
    currency, rate = currency_and_rate(date)
    { invoice_type: :supplier, document_type: value("document_type") == "credit_note" ? :credit_note : :invoice, status: :draft,
      partner: @partner, journal: Accounting::Journal.active.find_by(journal_type: :purchase), fiscal_year: fiscal_year,
      invoice_date: date, due_date: date_of("due_date"), supplier_reference: reference, currency: currency, exchange_rate: rate,
      description: "From document #{@document.name}",
      subtotal_excl_vat: amount("subtotal"), vat_amount: amount("vat_amount"), total_incl_vat: amount("total") }.compact
  end

  # EUR, or a supported currency only when its rate is known: a rate is never guessed.
  def currency_and_rate(date)
    code = value("currency").to_s.upcase
    return [ "EUR", BigDecimal("1") ] if code.blank? || code == "EUR" || Accounting::MoneyPresenter::SUPPORTED_CURRENCIES.exclude?(code)

    [ code, Fx::RateFor.call(code, document_date: date) ]
  rescue Fx::MissingRate
    [ "EUR", BigDecimal("1") ] # still a draft: the person enters the currency and its rate
  end

  def probable_duplicate(reference)
    return if reference.blank?

    Accounting::Invoice.supplier.where(partner: @partner, supplier_reference: reference).where.not(status: :cancelled).first
  end

  # What a person confirmed, else what was proposed; remembers which fields were only proposals.
  def field(name) = @document.extracted_data.dig("extraction", "fields", name)

  def value(name)
    found = field(name)
    return unless found

    @used[name] = found["confirmed"] == true
    found["value"]
  end

  def amount(name) = (raw = value(name)) && BigDecimal(raw.to_s)

  def date_of(name)
    raw = value(name)
    raw && Date.iso8601(raw.to_s)
  rescue Date::Error
    nil
  end

  # A frozen document keeps its kind; the others take the kind of what they justify.
  def classify
    return unless @document.other? && !@document.locked?

    @document.update!(kind: value("document_type") == "credit_note" ? :credit_note : :purchase_invoice)
  end

  def audit(invoice, duplicate)
    unconfirmed = @used.reject { |_, confirmed| confirmed }.keys
    Accounting::AuditLog.record!(auditable: @document, action: "document_invoice_draft", user: @user,
                                 payload: { invoice_id: invoice.id, partner_id: @partner.id, unconfirmed_fields: unconfirmed })
    return unless duplicate

    Accounting::AuditLog.record!(auditable: @document, action: "document_duplicate_override", user: @user, reason: @override_reason,
                                 payload: { invoice_id: invoice.id, existing_invoice_id: duplicate.id, supplier_reference: invoice.supplier_reference })
  end

  def refuse(reason, **extra)
    LightService::Context.make(invoice: nil, reason: reason, **extra).tap { |ctx| ctx.fail!(I18n.t("documents.errors.#{reason}", **extra)) }
  end
end
