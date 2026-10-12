# The pre-flight report of a payment batch (B01b §5 "Contrôles préalables"): deterministic, kept on the batch, and made again at the composition, at the request for
# approval and at the export, so that anything that changed meanwhile (an account blocked, an invoice held, one paid elsewhere) blocks the export.
# Errors block. Warnings need an acknowledgement with a reason, written by a person (Payments::AcknowledgeWarning); the acknowledgement holds for the same finding on a later run.
# Information is only told (what the SEPA character set changes in a name). The report names suppliers and masked accounts, never an IBAN in full.
class Payments::Preflight
  Finding = Struct.new(:code, :key, :message, keyword_init: true) do
    def to_h = { "code" => code.to_s, "key" => key, "message" => message }
  end
  Report = Struct.new(:errors, :warnings, :infos, :acknowledgements, :generated_at, keyword_init: true) do
    def ready? = errors.empty? && warnings.all? { |warning| acknowledgements.key?(warning.key) }
    def to_h = { "errors" => errors.map(&:to_h), "warnings" => warnings.map(&:to_h), "infos" => infos.map(&:to_h), "acknowledgements" => acknowledgements, "generated_at" => generated_at.iso8601 }
  end

  STRUCTURED = %r{\A(\+{3}\d{3}/\d{4}/\d{5}\+{3}|\d{12})\z}
  DUPLICATE_DAYS = 90
  NEW_ACCOUNT_DAYS = 30
  UNUSUAL_FACTOR = 2
  MIN_FOR_AVERAGE = 3

  def self.call(batch) = new(batch).call

  def initialize(batch)
    @batch = batch
    @profile = batch.bank_profile
    @errors = []
    @warnings = []
    @infos = []
  end

  def call
    check_dates_and_limits
    items.each { |item| check_account(item) }
    invoice_lines.each { |link| check_invoice(link) }
    check_totals
    warn_duplicates
    warn_balance
    warn_unusual_amounts
    warn_new_accounts
    tell_changes
    report = Report.new(errors: @errors, warnings: @warnings, infos: @infos, acknowledgements: (@batch.preflight_report || {}).fetch("acknowledgements", {}), generated_at: Time.current)
    @batch.update_columns(preflight_report: report.to_h)
    report
  end

  private

  def items = @items ||= @batch.items.where(status: :included).includes(:partner, :partner_bank_account, item_invoices: :invoice).order(:id).to_a

  def invoice_lines = @invoice_lines ||= items.flat_map { |item| item.item_invoices.map { |link| [ item, link ] } }

  def error(code, subject, message) = @errors << Finding.new(code: code, key: "#{code}:#{subject}", message: message)
  def warning(code, subject, message) = @warnings << Finding.new(code: code, key: "#{code}:#{subject}", message: message)
  def info(code, subject, message) = @infos << Finding.new(code: code, key: "#{code}:#{subject}", message: message)
  def money(value) = format("%.2f", value)

  def check_dates_and_limits
    date = @batch.requested_execution_date
    closed = Array(@profile&.options&.dig("closed_days"))
    if date < Date.current
      error(:execution_date, "date", "The execution date #{date.strftime('%d/%m/%Y')} is in the past.")
    elsif !Payments::SettlementCalendar.open?(date, extra_closed: closed)
      error(:execution_date, "date", "The execution date #{date.strftime('%d/%m/%Y')} is a day the banks do not settle: the next one is #{Payments::SettlementCalendar.next_open(date, extra_closed: closed).strftime('%d/%m/%Y')}.")
    end
    return unless @profile

    error(:limit_payments, "batch", "The batch has #{items.size} payments; the bank takes #{@profile.max_payments} in a file.") if @profile.max_payments && items.size > @profile.max_payments
    error(:limit_batch_total, "batch", "The batch totals #{money(@batch.total)}; the limit is #{money(@profile.max_batch_total)}.") if @profile.max_batch_total && @batch.total > @profile.max_batch_total
    return unless @profile.max_supplier_total

    items.group_by(&:partner).each do |partner, partner_items|
      total = partner_items.sum(&:amount)
      error(:limit_supplier_total, "partner#{partner.id}", "#{partner.name} is paid #{money(total)} in this batch; the limit to one supplier is #{money(@profile.max_supplier_total)}.") if total > @profile.max_supplier_total
    end
  end

  def check_account(item)
    snapshot = item.partner_bank_account
    current = usable_accounts[item.partner_id]
    if current && current.id != snapshot&.id
      error(:account_changed, "item#{item.id}", "#{item.partner.name} has another verified account now (#{current.masked_iban}): the batch was made with #{item.masked_iban}. Make the batch again.")
    elsif snapshot.nil? || !snapshot.usable?
      error(:account_not_usable, "item#{item.id}", "The bank account of #{item.partner.name} (#{item.masked_iban}) can no longer be paid: it is #{snapshot ? snapshot.status.humanize.downcase + (snapshot.verified? ? ', and observed' : '') : 'gone'}.")
    end
  end

  def check_invoice(link)
    item, link = link
    invoice = link.invoice
    label = "#{item.partner.name}, #{invoice.invoice_number || invoice.id}"
    error(:iban_differs, "invoice#{invoice.id}", "#{label}: the invoice carries another IBAN than the account paid.") if invoice.iban.present? && Accounting::Iban.normalize(invoice.iban) != item.iban
    error(:on_hold, "invoice#{invoice.id}", "#{label}: #{holds_text(invoice)}") if holds_for(invoice).any?
    return if invoice.credit_note?

    check_approval(invoice, label)
    rest = rests.fetch(invoice.id, 0)
    error(:rest_changed, "invoice#{invoice.id}", "#{label}: only #{money(rest)} is left to pay, and the batch pays #{money(link.amount)}.") if rest < link.amount
    return if invoice.payment_reference.blank? || !invoice.payment_reference.match?(STRUCTURED) || Accounting::StructuredCommunication.extract(invoice.payment_reference)

    error(:structured_communication, "invoice#{invoice.id}", "#{label}: the structured communication #{invoice.payment_reference} is not valid (its check digits do not agree).")
  end

  def check_approval(invoice, label)
    return unless @batch.entity.feature?(:b01a)

    if %w[to_approve on_hold disputed].include?(invoice.payment_status)
      error(:not_approved, "invoice#{invoice.id}", "#{label}: the invoice is #{invoice.payment_status.humanize.downcase}.")
    elsif invoice.payment_approved? && !Approvals::Request.approved.exists?(subject: invoice, content_fingerprint: Approvals::ContentFingerprint.call(invoice))
      error(:approval_stale, "invoice#{invoice.id}", "#{label}: the invoice changed since it was approved.")
    end
  end

  # The account each supplier of the batch can be paid on now, asked for all of them at once.
  def usable_accounts
    @usable_accounts ||= Accounting::PartnerBankAccount.where(partner_id: items.map(&:partner_id).uniq, status: :verified).where(cooling_until: ..Time.current)
                                                       .order(:verified_at).group_by(&:partner_id).transform_values(&:last)
  end

  def holds
    @holds ||= Payments::Hold.active.where(invoice_id: invoice_lines.map { |_, link| link.invoice_id }).or(Payments::Hold.active.where(partner_id: items.map(&:partner_id))).to_a
  end

  def holds_for(invoice) = holds.select { |hold| hold.invoice_id == invoice.id || hold.partner_id == invoice.partner_id }

  def holds_text(invoice) = "on hold: #{holds_for(invoice).map(&:reason).join('; ')}"

  def rests = @rests ||= Payments::OpenAmounts.rests(invoice_lines.map { |_, link| link.invoice }.uniq)

  def check_totals
    paid = items.sum(&:amount)
    lines = invoice_lines.sum { |_, link| link.amount }
    per_item = items.all? { |item| item.item_invoices.sum(&:amount) == item.amount }
    return if @batch.total == paid && paid == lines && per_item && @batch.payments_count == items.size

    error(:totals, "batch", "The totals do not agree: batch #{money(@batch.total)}, payments #{money(paid)}, invoices #{money(lines)}.")
  end

  def warn_duplicates
    earlier = Payments::Item.joins(:batch).where(partner_id: items.map(&:partner_id).uniq).where.not(batch_id: @batch.id).where.not(payment_batches: { status: Payments::Batch.statuses[:cancelled] })
                            .where("payment_batches.created_at >= ?", DUPLICATE_DAYS.days.ago).includes(:batch).group_by { |other| [ other.partner_id, other.amount, other.remittance ] }
    items.each do |item|
      twin = earlier[[ item.partner_id, item.amount, item.remittance ]]&.first
      warning(:probable_duplicate, "item#{item.id}", "#{item.partner.name}: #{money(item.amount)} with the same remittance was already in batch #{twin.batch.reference}.") if twin
    end
  end

  def warn_balance
    balance = Payments::Balance.of(@batch.bank_account) or return
    threshold = @profile&.balance_threshold || 0
    after = balance - @batch.total
    warning(:low_balance, "batch", "The balance of the account debited is #{money(balance)}; after this batch #{money(after)}, under #{money(threshold)}.") if after < threshold
  end

  def warn_unusual_amounts
    in_batch = invoice_lines.map { |_, link| link.invoice_id }
    past = Accounting::Invoice.supplier.invoice.where(partner_id: items.map(&:partner_id).uniq, currency: "EUR", status: %i[posted partially_paid paid]).where.not(id: in_batch)
                              .group_by(&:partner_id).transform_values { |list| list.sort_by { |i| [ i.invoice_date, i.id ] }.last(5) }
    items.each do |item|
      recent = past.fetch(item.partner_id, [])
      next if recent.size < MIN_FOR_AVERAGE

      average = recent.sum(&:total_incl_vat) / recent.size
      warning(:unusual_amount, "item#{item.id}", "#{item.partner.name}: #{money(item.amount)} is more than twice the usual invoice of this supplier (#{money(average)}).") if item.amount > UNUSUAL_FACTOR * average
    end
  end

  def warn_new_accounts
    recent = items.filter_map(&:partner_bank_account).uniq.select { |account| account.first_seen_at >= NEW_ACCOUNT_DAYS.days.ago }
    warning(:many_new_accounts, "batch", "#{recent.size} of the accounts paid in this batch are new or changed in the last #{NEW_ACCOUNT_DAYS} days.") if recent.size > 3
  end

  def tell_changes
    changed = items.filter_map { |item| [ item.partner.name, item.holder_name, item.remittance ].filter_map { |text| Payments::SepaText.changes(text) }.reduce({}, :merge).presence }.reduce({}, :merge)
    info(:transliterated, "batch", "The SEPA file cannot carry all the characters of some names: #{changed.map { |from, to| "\"#{from}\" becomes \"#{to}\"" }.join('; ')}.") if changed.any?
  end
end
