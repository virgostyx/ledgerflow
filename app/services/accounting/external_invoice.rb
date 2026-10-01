# Invoices injected by a third-party application (docs/dev/api/inbound-api.md), keyed by its own reference.
# `post: false` leaves the document a draft: the accountant codes it and posts it in LedgerFlow (default: posted at once).
# Credit notes are the same resource (document_type "credit_note", optionally linked to the credited invoice).
# - upsert: unknown reference -> create + post; identical replay -> no-op; changed content -> the current document
#   is cancelled (reversal) and a new revision is posted under the same reference, all or nothing. A draft nobody
#   touched is replaced in place; once the accountant has worked on it (external_state_digest), the change is refused.
#   In draft mode, a document the accountant has already posted cannot be corrected at all (409): the books are theirs.
# - cancel: reverses the current document, with a mandatory reason (recorded in the audit trail); a draft is just cancelled.
#   A document handed over as a draft and since booked is refused (409): the accountant returns it from LedgerFlow.
# Returns a Result whose status is :created, :ok, :unprocessable, :conflict or :not_found.
class Accounting::ExternalInvoice
  Result = Struct.new(:status, :invoice, :errors, keyword_init: true)

  # ponytail: no journal or credit-note choice yet; the journal follows the invoice type, as in the UI.
  ATTRIBUTES = %w[document_type invoice_type invoice_date due_date currency exchange_rate vat_treatment description notes project_id].freeze
  LINE_DECIMALS = %w[quantity unit_price vat_rate].freeze
  # A client working in draft mode hands the books to the accountant: once posted, only they can undo it, by returning it
  # to the project manager from LedgerFlow (neither a correction nor a deletion from the third party is accepted).
  BOOKED_BY_ACCOUNTANT = "Already booked in LedgerFlow: the accountant must return it to the project manager from LedgerFlow.".freeze

  def self.upsert(payload) = new.upsert(payload.to_h.with_indifferent_access)
  def self.cancel(external_ref:, reason:) = new.cancel(external_ref, reason)

  def upsert(payload)
    @external_ref = payload[:external_ref]
    @post         = payload[:post].nil? ? true : ActiveModel::Type::Boolean.new.cast(payload[:post])
    normalized = normalize(payload)
    # A date outside every open fiscal year is a state conflict, not a validation error.
    return failure(@period_closed && @errors.keys == [ :invoice_date ] ? :conflict : :unprocessable, @errors) if @errors.any?

    digest  = fingerprint(normalized)
    current = latest
    if current && current.document_type != normalized[:document_type]
      return failure(:unprocessable, document_type: [ "cannot change for an existing external_ref" ])
    end
    return Result.new(status: :ok, invoice: current) if current && !current.cancelled? && current.external_digest == digest
    return correct_draft(current, normalized, digest) if current&.draft?
    return failure(:conflict, base: [ BOOKED_BY_ACCOUNTANT ]) if current && !current.cancelled? && !@post

    write(current, normalized, digest)
  end

  def cancel(external_ref, reason)
    @external_ref = external_ref
    current = latest
    return failure(:not_found, base: [ "Unknown external_ref" ]) unless current
    return Result.new(status: :ok, invoice: current) if current.cancelled?
    # Handed over as a draft and now booked: only the accountant undoes it, by returning it from LedgerFlow.
    return failure(:conflict, base: [ BOOKED_BY_ACCOUNTANT ]) if !current.draft? && current.external_state_digest.present?
    return failure(:unprocessable, reason: [ "is required" ]) if reason.blank?

    with_reason(reason) { cancel_current(current) }
  end

  private

  def latest = Accounting::Invoice.external.where(external_ref: @external_ref).order(:revision).last

  def write(current, normalized, digest)
    result  = nil
    revised = current && !current.cancelled?
    ApplicationRecord.transaction(requires_new: true) do
      if revised
        cancelled = with_reason("Revised by #{author} (revision #{current.revision + 1})") { cancel_current(current) }
        unless cancelled.status == :ok
          result = cancelled
          raise ActiveRecord::Rollback
        end
      end
      result = create_and_post(current, normalized, digest)
      raise ActiveRecord::Rollback unless result.status == :created
    end
    # Correcting a live document is an update for the caller (200); a first or post-cancellation document is a creation.
    result.status = :ok if revised && result.status == :created
    result
  rescue ActiveRecord::RecordNotUnique
    # Lost a race against a concurrent request for the same reference: nothing was written, the caller retries.
    failure(:conflict, base: [ "Concurrent update, retry" ])
  end

  # A draft has no entry to reverse.
  def cancel_current(invoice)
    return cancel_draft(invoice) if invoice.draft?

    done = Accounting::CancelInvoice.call(invoice: invoice)
    done.success? ? Result.new(status: :ok, invoice: invoice.reload) : failure(:conflict, base: [ done.message ])
  end

  def create_and_post(current, normalized, digest)
    invoice = Accounting::Invoice.new(invoice_attributes(normalized, digest).merge(
      external_ref: @external_ref, revision: (current&.revision || 0) + 1))
    normalized[:lines_attrs].each_with_index { |line, i| invoice.lines.build(line.merge(position: i + 1)) }
    return failure(:unprocessable, invoice.errors.to_hash) unless invoice.save

    settle(invoice)
  end

  def invoice_attributes(normalized, digest)
    normalized.slice(*ATTRIBUTES.map(&:to_sym)).merge(
      partner: normalized[:partner], fiscal_year: normalized[:fiscal_year], credited_invoice: normalized[:credited_invoice],
      external_project_name: normalized[:external_project_name], external_budget_line: normalized[:external_budget_line],
      external_digest: digest)
  end

  # A document just saved: left as a draft, or posted at once.
  def settle(invoice)
    return draft_result(invoice) unless @post

    posted = Accounting::PostInvoice.call(invoice: invoice)
    return failure(:unprocessable, base: [ posted.message ]) if posted.failure?

    Result.new(status: :created, invoice: invoice.reload)
  end

  # A draft still shows its totals (PostInvoice would compute them when posting), and remembers what the API wrote.
  def draft_result(invoice)
    invoice.compute_totals
    invoice.save!
    invoice.update_columns(external_state_digest: state_digest(invoice.reload))
    Result.new(status: :created, invoice: invoice)
  end

  # The third party corrects a draft: replaced in place while the accountant has not worked on it, refused after.
  def correct_draft(current, normalized, digest)
    unless current.external_state_digest.present? && current.external_state_digest == state_digest(current)
      return failure(:conflict, base: [ "The accountant is already processing this draft: ask for it to be returned first." ])
    end

    result = nil
    ApplicationRecord.transaction(requires_new: true) do
      current.lines.destroy_all
      reset_omitted_attributes(current, normalized)
      current.assign_attributes(invoice_attributes(normalized, digest))
      normalized[:lines_attrs].each_with_index { |line, i| current.lines.build(line.merge(position: i + 1)) }
      result = current.save ? settle(current) : failure(:unprocessable, current.errors.to_hash)
      raise ActiveRecord::Rollback unless result.status == :created
    end
    result.status = :ok if result.status == :created
    result
  end

  # What the new payload leaves out goes back to the default, it does not keep an earlier value.
  def reset_omitted_attributes(invoice, normalized)
    (ATTRIBUTES.map(&:to_sym) - normalized.keys).each { |key| invoice[key] = Accounting::Invoice.column_defaults[key.to_s] }
    invoice.send(:default_due_date) if normalized[:due_date].nil?
  end

  def cancel_draft(invoice)
    invoice.cancel!
    Result.new(status: :ok, invoice: invoice)
  end

  # Header, lines and analytical annotations as they are in the database now.
  def state_digest(invoice)
    lines = invoice.lines.includes(:account, :analytical_annotations).map do |l|
      [ l.account.code, l.description, l.quantity, l.unit_price, l.vat_rate,
        l.analytical_annotations.map { |a| [ a.analytical_axis_id, a.analytical_account_id ] }.sort ]
    end
    header = invoice.slice(*ATTRIBUTES, :partner_id, :credited_invoice_id, :external_project_name, :external_budget_line)
    Digest::SHA256.hexdigest(JSON.generate(canonical(header: header, lines: lines)))
  end

  # Validates and converts the payload; fills @errors. Amounts go through BigDecimal, never Float.
  def normalize(payload)
    @errors = {}
    n = payload.slice(*ATTRIBUTES).symbolize_keys.compact
    n[:document_type] = enum_value(n.reverse_merge(document_type: "invoice"), :document_type, Accounting::Invoice.document_types)
    n[:invoice_type]  = enum_value(n, :invoice_type, Accounting::Invoice.invoice_types)
    n[:vat_treatment] = enum_value(n, :vat_treatment, Accounting::Invoice.vat_treatments) if n.key?(:vat_treatment)
    n[:currency] = n[:currency].to_s.upcase if n.key?(:currency)
    %i[invoice_date due_date].each { |k| n[k] = date(n[k], k) if n.key?(k) }
    n[:exchange_rate] = decimal(n[:exchange_rate], :exchange_rate) if n.key?(:exchange_rate)
    n[:partner]     = partner(payload[:partner_external_ref])
    n[:fiscal_year] = fiscal_year(n[:invoice_date])
    n[:lines_attrs] = lines(payload[:lines])
    n[:external_project_name] = payload[:project_name].to_s.strip.presence
    n[:external_budget_line]  = payload[:budget_line].to_s.strip.presence
    n[:credited_invoice] = credited_invoice(payload[:credited_invoice_external_ref], n[:document_type])
    n
  end

  def enum_value(n, key, allowed)
    value = n[key].to_s
    return value if allowed.key?(value)

    @errors[key] = [ "must be one of #{allowed.keys.join(', ')}" ]
    nil
  end

  def date(value, key)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    @errors[key] = [ "must be an ISO 8601 date" ]
    nil
  end

  def decimal(value, key)
    number = BigDecimal(value.to_s, exception: false)
    return number if number&.finite?

    @errors[key] = [ "must be a number" ]
    nil
  end

  def partner(ref)
    found = Accounting::Partner.find_by(external_ref: ref) if ref.present?
    @errors[:partner_external_ref] = [ "unknown partner, send it first via PUT /api/v1/partners/:external_ref" ] unless found
    found
  end

  # Only a live API-managed invoice can be credited; the model then checks partner, type and VAT treatment.
  def credited_invoice(ref, document_type)
    return if ref.blank?

    unless document_type == "credit_note"
      @errors[:credited_invoice_external_ref] = [ "is only allowed on a credit note" ]
      return
    end
    found = Accounting::Invoice.external.where(external_ref: ref).order(:revision).last
    found = nil if found&.cancelled?
    @errors[:credited_invoice_external_ref] = [ "unknown or cancelled document #{ref.inspect}" ] unless found
    found
  end

  def fiscal_year(invoice_date)
    return unless invoice_date

    found = Accounting::FiscalYear.open_years.find_by("start_date <= :d AND end_date >= :d", d: invoice_date)
    @errors[:invoice_date] = [ "no open fiscal year covers this date" ] unless found
    @period_closed = found.nil?
    found
  end

  def lines(raw)
    list = Array(raw)
    if list.empty?
      @errors[:lines] = [ "at least one line is required" ]
      return []
    end

    codes    = list.map { |l| l[:account_code].to_s.strip.presence || Accounting::AccountCodes::TRANSIT }.uniq
    accounts = Accounting::Account.where(code: codes).index_by(&:code)
    list.each_with_index.map do |line, i|
      line    = line.to_h.with_indifferent_access
      given   = line[:account_code].to_s.strip.presence
      account = accounts[given || Accounting::AccountCodes::TRANSIT]
      @errors["lines[#{i}].account_code"] = [ account_error(given) ] unless account
      attrs = { account: account, description: line[:description] }
      LINE_DECIMALS.each { |k| attrs[k.to_sym] = decimal(line[k], "lines[#{i}].#{k}") if line.key?(k) }
      attrs.compact
    end
  end

  # A line sent without an account goes on the suspense account; the accountant codes it before posting.
  def account_error(given)
    given ? "unknown account #{given.inspect}" : "no account code, and the suspense account #{Accounting::AccountCodes::TRANSIT} is missing from the chart"
  end

  # Same content, same fingerprint, whatever the number formatting of the caller (0.1 or "0.10").
  def fingerprint(n)
    content = { post: @post, partner_id: n[:partner].id, credited_invoice_id: n[:credited_invoice]&.id,
                context: n.slice(:external_project_name, :external_budget_line),
                invoice: n.slice(*ATTRIBUTES.map(&:to_sym)),
                lines: n[:lines_attrs].map { |l| l.merge(account: l[:account].code) } }
    Digest::SHA256.hexdigest(JSON.generate(canonical(content)))
  end

  def canonical(value)
    case value
    when Hash then value.sort_by { |k, _| k.to_s }.to_h { |k, v| [ k.to_s, canonical(v) ] }
    when Array then value.map { |v| canonical(v) }
    when BigDecimal then value.to_s("F")
    else value.as_json
    end
  end

  def with_reason(reason)
    Current.reason = reason
    yield
  ensure
    Current.reason = nil
  end

  def author = Current.api_client&.name || "third-party application"

  def failure(status, errors)
    Result.new(status: status, errors: errors)
  end
end
