# A person confirms that the bank debited a payment batch (B01c §6 "Confirmation du paiement"), from the line of the statement or, when the statement has none, by hand.
# One DRAFT entry per payment: debit the suppliers' account on each invoice paid (credit it for a credit note netted), credit the bank, dated as the line, referenced as the
# end-to-end id of the payment, tied to the payment (`source`). Never two entries for one payment. Nothing is validated and nothing lettered here: that is Payments::PostBatchPayments,
# by another right (`entries.post`). The invoices stay held until their entry is validated.
# call: a line of the statement and the payments it paid (all of the batch, or some of them when the bank lists payments one by one).
# manual: no line found; a reason, a date and the reference of the bank are kept, and the batch must have been said to be loaded in the bank. => ctx[:entries]; on a refusal ctx[:code].
class Payments::ConfirmDebit
  WAITING = %w[exported submitted cancel_requested].freeze

  def self.call(batch:, user:, transaction:, items: nil)
    ctx = LightService::Context.make(entries: [])
    items = Array(items.presence || batch.items.select(&:included?))
    code = refusal_for(batch, user, transaction, items)
    return refuse(ctx, code) if code

    book(ctx, batch, user, items, transaction.transaction_date, transaction, kind: "statement", audit: "payment_batch_debit_confirmed", extra: { transaction_id: transaction.id })
  end

  def self.manual(batch:, user:, reason:, date:, bank_reference:)
    ctx = LightService::Context.make(entries: [])
    code = base_refusal(batch, user) || (:reason_required if reason.to_s.strip.empty?) || (:date_required if date.blank?) || (:reference_required if bank_reference.to_s.strip.empty?) ||
           (:not_submitted unless batch.submitted?)
    return refuse(ctx, code) if code

    book(ctx, batch, user, batch.items.select(&:included?), date, nil, kind: "manual", audit: "payment_batch_debit_confirmed_by_hand",
                                                                       extra: { reason: reason.to_s.strip, bank_reference: bank_reference.to_s.strip, date: date.to_date.iso8601 },
                                                                       fields: { debit_reason: reason.to_s.strip, debit_reference: bank_reference.to_s.strip, debit_date: date })
  end

  def self.base_refusal(batch, user)
    return :feature_off unless batch.entity.feature?(:b01b)
    return :not_allowed unless Payments::BatchPolicy.new(user, batch).confirm?

    :not_waiting unless WAITING.include?(batch.status)
  end
  private_class_method :base_refusal

  def self.refusal_for(batch, user, transaction, items)
    base_refusal(batch, user) ||
      (:not_a_debit unless transaction.debit?) || (:line_not_pending unless transaction.pending?) || (:wrong_account if transaction.bank_account_id != batch.bank_account_id) ||
      (:foreign_items unless items.any? && (items.map(&:id) - batch.items.where(status: :included).pluck(:id)).empty?) ||
      (:amount_mismatch if items.sum(&:amount) != -transaction.amount) || (:no_fiscal_year unless fiscal_year_for(transaction.transaction_date))
  end
  private_class_method :refusal_for

  def self.fiscal_year_for(date) = Accounting::FiscalYear.open_years.where("start_date <= ? AND end_date >= ?", date, date).first
  private_class_method :fiscal_year_for

  def self.book(ctx, batch, user, items, date, transaction, kind:, audit:, extra:, fields: {})
    return refuse(ctx, :no_fiscal_year) unless (fiscal_year = fiscal_year_for(date))

    ApplicationRecord.transaction do
      Payments::Batch.lock.find(batch.id) # one confirmation at a time
      next refuse(ctx, :not_waiting) unless WAITING.include?(batch.reload.status)
      next refuse(ctx, :already_confirmed) unless (items.map(&:id) - batch.items.where(status: :included).pluck(:id)).empty?
      next refuse(ctx, :line_not_pending) if transaction && !transaction.reload.pending?

      items = Payments::Item.where(id: items.map(&:id)).includes(:partner, :journal_entry, item_invoices: :invoice).order(:id).to_a # read together: no query per payment
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      journal = batch.bank_account.journal
      suppliers = Accounting::Account.find_by!(code: Accounting::AccountCodes::SUPPLIERS)
      ctx[:entries] = items.map { |item| entry_for(batch, item, user, date, fiscal_year, journal, suppliers) }
      now = Time.current
      items.each_with_index { |item, i| item.update!(status: :confirmed, journal_entry: ctx[:entries][i], bank_transaction: transaction, confirmed_by: user, confirmed_at: now) }
      transaction&.update!(status: :matched, match_data: { "kind" => "payment_batch", "batch_id" => batch.id, "item_ids" => items.map(&:id), "entry_ids" => ctx[:entries].map(&:id) })
      settle(batch, user, now, kind, fields)
      Accounting::AuditLog.record!(auditable: batch, action: audit, user: user,
                                   payload: { entries: items.size, total: format("%.2f", items.sum(&:amount)), message_id: batch.message_id }.merge(extra))
    end
    ctx
  end
  private_class_method :book

  # The batch is debited once no payment of it waits any more.
  def self.settle(batch, user, now, kind, fields)
    return if batch.items.reload.any?(&:included?)

    batch.update!({ status: batch.items.any?(&:rejected?) ? :partially_rejected : :debited, debited_at: now, debited_by: user, debit_kind: kind }.merge(fields))
  end
  private_class_method :settle

  def self.entry_for(batch, item, user, date, fiscal_year, journal, suppliers)
    label = "Batch #{batch.reference} - #{item.partner.name}"
    entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: item.end_to_end_id, description: label,
                                             status: :draft, source_type: "Payments::Item", source_id: item.id, created_by: user)
    item.item_invoices.sort_by(&:id).each do |link|
      paid = link.amount.positive?
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: suppliers, partner: item.partner, invoice: link.invoice, label: label, debit: paid ? link.amount : 0, credit: paid ? 0 : -link.amount)
    end
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: journal.default_account, label: label, debit: 0, credit: item.amount)
    entry
  end
  private_class_method :entry_for

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.debit.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end
