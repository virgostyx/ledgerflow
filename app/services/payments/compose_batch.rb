# Composes a payment batch from eligible invoices (B01b §5 "Composition du lot"), all or nothing. One payment per supplier: the invoices that carry a structured
# communication are paid on their own, with it; the others are grouped, with a free remittance that lists their numbers (140 characters at most). An amount below the rest
# of an invoice is a part payment. With `net_credit_notes`, the open credit notes of a supplier are netted against its grouped invoices: the payment is the net, and the notes
# are used up; when they cover the invoices there is no payment and the supplier is listed in `to_net`, for a lettering by hand (F04).
# The account paid is the verified one, as it is now (a snapshot). Nothing is made when anything is wrong, or when another batch took an invoice meanwhile (the database
# guarantees that an invoice is in one active batch at most).
# selections: [{ invoice_id:, amount: (optional, below the rest) }]. => ctx[:batch], ctx[:to_net] (the suppliers netted to nothing); on a refusal the reasons in the message.
class Payments::ComposeBatch
  REMITTANCE_LENGTH = 140

  def self.call(bank_account:, execution_date:, selections:, user:, net_credit_notes: false) = new(bank_account, execution_date, selections, user, net_credit_notes).call

  def initialize(bank_account, execution_date, selections, user, net_credit_notes)
    @bank_account = bank_account
    @execution_date = execution_date
    @selections = Array(selections)
    @user = user
    @net = net_credit_notes
  end

  def call
    ctx = LightService::Context.make(batch: nil, to_net: [])
    entity = @bank_account.entity
    return fail!(ctx, :feature_off) unless entity.feature?(:b01b)
    return fail!(ctx, :not_allowed) unless Payments::BatchPolicy.new(@user, nil).prepare?
    return fail!(ctx, :not_euro) unless @bank_account.currency == "EUR"
    return fail!(ctx, :nothing_selected) if @selections.empty?

    problem = pick_invoices
    return refuse(ctx, problem) if problem

    ApplicationRecord.transaction do
      ctx[:to_net] = []
      payments = build_payments(ctx)
      raise ActiveRecord::Rollback, "nothing to pay" if payments.empty? && (ctx.fail!(I18n.t("payments.compose.nothing_to_pay")) || true)

      ctx[:batch] = persist(payments)
    end
    ctx
  rescue ActiveRecord::RecordNotUnique
    ctx[:batch] = nil
    refuse(ctx, I18n.t("payments.compose.taken_meanwhile"))
  end

  private

  Payment = Struct.new(:partner, :account, :amount, :lines, :structured, :remittance, keyword_init: true)

  # Each selected invoice with the amount asked for, and the eligibility row that says whether it can be paid. => nil, or what is wrong, in words
  def pick_invoices
    ids = @selections.map { |s| s[:invoice_id].to_i }
    return I18n.t("payments.compose.twice") if ids.uniq.size != ids.size

    rows = Payments::Eligibility.call(execution_date: @execution_date).index_by { |row| row.invoice.id }
    @rows = rows
    @credit_rows = rows.values.select { |row| row.invoice.credit_note? && row.reasons.map(&:code) == [ :credit_note ] }
    @chosen = []
    problems = @selections.flat_map do |selection|
      row = rows[selection[:invoice_id].to_i]
      next [ I18n.t("payments.compose.unknown_invoice", id: selection[:invoice_id]) ] unless row

      label = "#{row.invoice.partner.name}, #{row.invoice.invoice_number || row.invoice.id}"
      next row.reasons.map { |reason| "#{label}: #{reason.message}" } unless row.eligible?

      amount = parse_amount(selection[:amount], row.rest)
      next [ "#{label}: #{I18n.t('payments.compose.bad_amount', rest: row.rest.to_s('F'))}" ] unless amount

      @chosen << [ row, amount ]
      []
    end
    problems.join(" ") if problems.any?
  end

  def parse_amount(value, rest)
    return rest if value.nil? || value.to_s.strip.empty?

    amount = BigDecimal(value.to_s, exception: false)
    amount if amount && amount.positive? && amount <= rest && amount == amount.round(2)
  end

  def build_payments(ctx)
    @chosen.group_by { |row, _| row.invoice.partner }.sort_by { |partner, _| partner.name }.flat_map do |partner, chosen|
      structured, grouped = chosen.partition { |row, _| structured_digits(row.invoice) }
      payments = structured.map { |row, amount| payment(partner, row.account, [ [ row.invoice, amount ] ], structured: structured_digits(row.invoice)) }
      payments << grouped_payment(ctx, partner, grouped) if grouped.any?
      payments.compact
    end
  end

  def structured_digits(invoice) = Accounting::StructuredCommunication.extract(invoice.payment_reference)

  def payment(partner, account, lines, structured: nil)
    Payment.new(partner: partner, account: account, lines: lines, amount: lines.sum { |_, amount| amount }, structured: structured, remittance: structured || free_remittance(lines.map(&:first)))
  end

  # The grouped invoices of a supplier, net of its credit notes when asked.
  def grouped_payment(ctx, partner, grouped)
    lines = grouped.map { |row, amount| [ row.invoice, amount ] }
    account = grouped.first.first.account
    return payment(partner, account, lines) unless @net

    gross = lines.sum { |_, amount| amount }
    remaining = gross
    credits = []
    @credit_rows.select { |row| row.invoice.partner_id == partner.id }.sort_by { |row| [ row.invoice.invoice_date, row.invoice.id ] }.each do |row|
      use = [ row.rest.abs, remaining ].min
      next unless use.positive?

      credits << [ row.invoice, -use ]
      remaining -= use
    end
    return payment(partner, account, lines + credits) if remaining.positive?

    ctx[:to_net] << partner # the credit notes cover the invoices: nothing to pay, nothing consumed, a lettering by hand
    nil
  end

  def free_remittance(invoices)
    numbers = invoices.map { |invoice| invoice.supplier_reference.presence || invoice.invoice_number || invoice.id.to_s }
    text = (numbers.size == 1 ? "Invoice " : "Invoices ") + numbers.join(", ")
    return text if text.length <= REMITTANCE_LENGTH

    shown = []
    numbers.each_with_index do |number, index|
      candidate = "Invoices #{(shown + [ number ]).join(', ')} and #{numbers.size - index - 1} more"
      break if candidate.length > REMITTANCE_LENGTH

      shown << number
    end
    "Invoices #{shown.join(', ')} and #{numbers.size - shown.size} more"
  end

  def persist(payments)
    batch = Payments::Batch.create!(bank_account: @bank_account, reference: next_reference, requested_execution_date: @execution_date, prepared_by: @user, prepared_at: Time.current)
    payments.each_with_index do |payment, index|
      account = payment.account
      item = batch.items.create!(partner: payment.partner, partner_bank_account: account, iban: account.iban, bic: account.bic, holder_name: account.holder_name, amount: payment.amount,
                                 end_to_end_id: "#{batch.reference}-#{index + 1}", remittance: payment.remittance, structured_remittance: payment.structured.present?)
      payment.lines.each { |invoice, amount| item.item_invoices.create!(invoice: invoice, amount: amount) }
    end
    batch.update_columns(total: payments.sum(&:amount), payments_count: payments.size)
    Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_composed", user: @user,
                                 payload: { reference: batch.reference, total: format("%.2f", batch.reload.total), payments: batch.payments_count, execution_date: @execution_date.iso8601, net_credit_notes: @net })
    batch
  end

  # PAY-2026-0001, one after the other within the year; two people composing at once do not get the same one.
  def next_reference
    ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext('payment_batch_reference'), #{ActsAsTenant.current_tenant.id.to_i})")
    prefix = "PAY-#{Date.current.year}-"
    last = Payments::Batch.where("reference LIKE ?", "#{prefix}%").pluck(:reference).filter_map { |reference| reference.delete_prefix(prefix).to_i if reference.match?(/\A#{prefix}\d+\z/) }.max || 0
    format("#{prefix}%04d", last + 1)
  end

  def fail!(ctx, code)
    ctx.fail!(I18n.t("payments.compose.#{code}"))
    ctx
  end

  def refuse(ctx, message)
    ctx.fail!(message)
    ctx
  end
end
