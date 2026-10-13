# Validates the draft entries of a debited batch together, and letters each payment with the invoice it pays (B01c §6 "Confirmation du paiement", steps 4 to 6).
# By a person with `entries.post` - another one than the preparer when the company asks for four eyes - and all or nothing. The lettering that follows is the one exception to manual
# validation: exact (the payment against the payable line of its invoice), deterministic and reversible (F04); a part payment letters partly and leaves the rest open.
# A payment of an invoice that is no longer open - settled meanwhile - is a probable double payment: nothing is lettered for it, the invoice is disputed, a task is made. The
# money has left the bank: the entry is validated and its debit stays open on the supplier until a person decides.
# => ctx[:posted], ctx[:lettered]; on a refusal ctx[:code]
class Payments::PostBatchPayments
  def self.call(batch:, user:)
    ctx = LightService::Context.make(posted: 0, lettered: 0, disputed: [])
    code = refusal_for(batch, user)
    return refuse(ctx, code) if code

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id)
      items = batch.reload.items.includes(:bank_transaction, :item_invoices, :partner, journal_entry: :lines).select { |item| item.confirmed? && item.journal_entry&.draft? }
      next refuse(ctx, :nothing_to_post) if items.empty?

      Current.set(user: user) { items.each { |item| post(ctx, item) } }
      next if ctx.failure?

      finish(ctx, batch, user, items)
    end
    ctx
  rescue Accounting::PostRefused => e
    ctx[:code] = :refused
    ctx.fail!(e.message)
    ctx
  end

  def self.refusal_for(batch, user)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :not_allowed unless Payments::BatchPolicy.new(user, batch).post_entries?
    return :own_batch if batch.entity.four_eyes? && batch.prepared_by_id == user.id

    :not_debited unless batch.debited? || batch.partially_rejected?
  end
  private_class_method :refusal_for

  def self.post(ctx, item)
    posted = Accounting::PostJournalEntry.call(entry: item.journal_entry, keep_reference: true)
    raise Accounting::PostRefused, posted.message if posted.failure?

    ctx[:posted] += 1
    letter(ctx, item.journal_entry.reload, item)
    item.refresh_holds!
  end
  private_class_method :post

  # Each payment line against the line of its own invoice: a payment (debit) against the payable line (credit), a credit note netted (credit) against its own (debit).
  def self.letter(ctx, entry, item)
    suppliers = Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS)
    entry.lines.where(account: suppliers).where.not(invoice_id: nil).includes(:invoice).order(:id).each do |payment|
      invoice_line = payment.invoice.journal_entry&.lines&.find_by(account: suppliers)
      next unless invoice_line

      if settled_already?(invoice_line, payment)
        dispute(ctx, item, payment.invoice)
      elsif Accounting::AllocateLines.call(lines: [ invoice_line, payment ]).success?
        ctx[:lettered] += 1
        Accounting::SyncInvoiceStatus.call([ invoice_line ])
        payment.invoice.reload.update_columns(payment_status: Accounting::Invoice.payment_statuses[:paid]) if payment.invoice.reload.paid?
      end
    end
  end
  private_class_method :letter

  # What the invoice still asks for is less than this payment: it was settled by something else.
  def self.settled_already?(invoice_line, payment)
    invoice_line.reload
    invoice_line.lettering_id.present? || invoice_line.open_amount < payment.debit + payment.credit
  end
  private_class_method :settled_already?

  def self.dispute(ctx, item, invoice)
    invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[:disputed])
    ctx[:disputed] << invoice.id
    task = Accounting::Task.create!(title: "Probable double payment of invoice #{invoice.invoice_number} (#{invoice.partner.name})", kind: :to_check, priority: :high, target: invoice,
                                    description: "The batch #{item.batch.reference} paid #{format('%.2f', item.amount)} and the invoice was already settled. Nothing was lettered: ask the supplier for a refund or letter the payment elsewhere.")
    Accounting::AuditLog.record!(auditable: item.batch, action: "payment_batch_double_payment_suspected", user: Current.user, payload: { invoice_id: invoice.id, item_id: item.id, task_id: task.id })
  end
  private_class_method :dispute

  def self.finish(ctx, batch, user, items)
    items.map(&:bank_transaction).compact.uniq.each do |line|
      line.update!(status: :reconciled) if line.payment_items.all? { |i| i.journal_entry&.posted? }
    end
    Accounting::AuditLog.record!(auditable: batch, action: "payment_batch_entries_posted", user: user, payload: { entries: ctx[:posted], lettered: ctx[:lettered], disputed: ctx[:disputed] })
  end
  private_class_method :finish

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.post.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end
