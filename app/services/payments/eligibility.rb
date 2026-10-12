# Which purchase invoices can be paid (B01b §5 "Éligibilité d'une facture"), each with the exact reasons it cannot, so that nothing is hidden: an invoice with
# several reasons shows them all. Listed: the supplier invoices and credit notes that are posted and not yet paid; drafts, cancelled and paid ones are not payable at all.
# An invoice is eligible when: its rest is open, its approval is given (or none is needed), nothing holds it, it is in no other active batch, its supplier has a verified bank
# account that is no longer observed, the IBAN it carries (if any) is that account, and it is in euros. A credit note is never paid: it is netted when a batch is made.
# Due date: `preselected` is what falls due up to the execution date plus the window (overdue included); a later one is offered as `early`, for a person to pick.
# Everything is read in a handful of queries whatever the number of invoices.
class Payments::Eligibility
  Reason = Struct.new(:code, :message)
  Row = Struct.new(:invoice, :reasons, :rest, :account, :early, :late, keyword_init: true) do
    def eligible? = reasons.empty?
    def early? = early
    def late? = late
    def preselected? = eligible? && !early
  end

  DEFAULT_WINDOW_DAYS = 7

  def self.call(execution_date:, window_days: DEFAULT_WINDOW_DAYS) = new(execution_date, window_days).rows

  def initialize(execution_date, window_days)
    @execution_date = execution_date
    @window_end = execution_date + window_days
    @today = Date.current
  end

  def rows
    return [] if invoices.empty?

    invoices.map { |invoice| row_for(invoice) }.sort_by { |row| [ row.invoice.due_date || Date.new(9999), row.invoice.partner.name ] }
  end

  private

  def invoices
    @invoices ||= Accounting::Invoice.supplier.where(status: %i[posted partially_paid]).includes(:partner).to_a
  end

  def row_for(invoice)
    reasons = invoice.credit_note? ? credit_note_reasons(invoice) : reasons_for(invoice)
    due = invoice.due_date
    Row.new(invoice: invoice, reasons: reasons, rest: rests.fetch(invoice.id, BigDecimal("0")), account: usable_account(invoice.partner_id),
            early: due.present? && due > @window_end, late: due.present? && due < @today)
  end

  # A credit note is never paid. It can be netted against the invoices of its supplier when nothing else stops it (so `[:credit_note]` alone means: usable for a netting).
  CREDIT_NOTE_IRRELEVANT = %i[no_account account_unverified account_observed account_blocked iban_differs].freeze

  def credit_note_reasons(invoice)
    [ Reason.new(:credit_note, "A credit note is not paid: it is netted against the invoices of the supplier when a batch is made.") ] +
      reasons_for(invoice, credit_note: true).reject { |reason| CREDIT_NOTE_IRRELEVANT.include?(reason.code) }
  end

  def reasons_for(invoice, credit_note: false)
    reasons = []
    open = credit_note ? rests.fetch(invoice.id, 0).negative? : rests.fetch(invoice.id, 0).positive?
    reasons << Reason.new(:nothing_open, "Nothing is left to pay on this invoice.") unless open
    reasons.concat(approval_reasons(invoice))
    reasons.concat(hold_reasons(invoice))
    reasons << in_batch_reason(invoice) if in_batch_reason(invoice)
    reasons << Reason.new(:currency, "The invoice is in #{invoice.currency}: SEPA batches pay in EUR only. Record the payment by hand.") if invoice.currency != "EUR"
    reasons.concat(account_reasons(invoice))
    reasons
  end

  def approval_reasons(invoice)
    case invoice.payment_status
    when "to_approve" then invoice.entity.feature?(:b01a) ? [ Reason.new(:awaiting_approval, "The invoice is waiting for its approval.") ] : []
    when "on_hold" then [ Reason.new(:on_hold, "The invoice is on hold: it was refused, sent back for changes, or its payment came back.") ]
    when "disputed" then [ Reason.new(:disputed, "The invoice is disputed.") ]
    else []
    end
  end

  def hold_reasons(invoice)
    (holds[[ :invoice, invoice.id ]] + holds[[ :partner, invoice.partner_id ]]).map { |hold| Reason.new(:hold, "On hold: #{hold.reason}") }
  end

  def in_batch_reason(invoice)
    @in_batch ||= {}
    @in_batch.fetch(invoice.id) do
      @in_batch[invoice.id] = if (link = new_flow_batches[invoice.id])
        Reason.new(:in_batch, "Already in payment batch #{link.item.batch.reference}.")
      elsif legacy_batches.key?(invoice.id)
        Reason.new(:in_batch, "Already in payment batch ##{legacy_batches[invoice.id]} (earlier flow).")
      end
    end
  end

  def account_reasons(invoice)
    accounts = accounts_by_partner[invoice.partner_id] || []
    usable = usable_account(invoice.partner_id)
    return [ Reason.new(:iban_differs, "The IBAN on the invoice differs from the verified account of the supplier: verify that account first (Bank details).") ] if usable && differs?(invoice, usable)
    return [] if usable

    observed = accounts.select(&:verified?).max_by(&:verified_at)
    if observed then [ Reason.new(:account_observed, "The bank account of the supplier is observed until #{observed.cooling_until.strftime('%d/%m/%Y %H:%M')}.") ]
    elsif accounts.any?(&:unverified?) then [ Reason.new(:account_unverified, "The bank account of the supplier has not been verified yet (Bank details).") ]
    elsif accounts.any?(&:blocked?) then [ Reason.new(:account_blocked, "The bank account of the supplier is blocked: register and verify another (Bank details).") ]
    else [ Reason.new(:no_account, "No bank account is registered for this supplier: register one under Bank details.") ]
    end
  end

  def differs?(invoice, account) = invoice.iban.present? && Accounting::Iban.normalize(invoice.iban) != account.iban

  def usable_account(partner_id) = (accounts_by_partner[partner_id] || []).select(&:usable?).max_by(&:verified_at)

  def accounts_by_partner
    @accounts_by_partner ||= Accounting::PartnerBankAccount.where(partner_id: invoices.map(&:partner_id).uniq).live.group_by(&:partner_id)
  end

  # What is left to pay on each invoice, in the currency of the entity: the open residual of the line of its entry on the suppliers' account (found through the entry,
  # as the rest of the application finds it), added up by the database.
  def rests
    @rests ||= begin
      by_entry = Accounting::OpenLineSql.open_scope(kind: :supplier, as_of: @today).where(journal_entry_id: invoices.filter_map(&:journal_entry_id))
                                        .group("accounting_journal_entry_lines.journal_entry_id").sum(Arel.sql("(#{Accounting::OpenLineSql.residual(kind: :supplier, as_of: @today)})"))
      invoices.to_h { |invoice| [ invoice.id, by_entry.fetch(invoice.journal_entry_id, BigDecimal("0")) ] }
    end
  end

  def holds
    @holds ||= Hash.new { |hash, key| hash[key] = [] }.tap do |index|
      Payments::Hold.active.where(invoice_id: invoices.map(&:id)).or(Payments::Hold.active.where(partner_id: invoices.map(&:partner_id).uniq)).each do |hold|
        index[[ :invoice, hold.invoice_id ]] << hold if hold.invoice_id
        index[[ :partner, hold.partner_id ]] << hold if hold.partner_id
      end
    end
  end

  def new_flow_batches
    @new_flow_batches ||= Payments::ItemInvoice.where(active: true, invoice_id: invoices.map(&:id)).includes(item: :batch).index_by(&:invoice_id)
  end

  def legacy_batches
    @legacy_batches ||= Accounting::PaymentBatchLine.active.where(invoice_id: invoices.map(&:id)).pluck(:invoice_id, :payment_batch_id).to_h
  end
end
