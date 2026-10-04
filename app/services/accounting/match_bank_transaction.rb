# Suggests what a bank transaction corresponds to, with a score (F02 spec, "Rapprochement automatique"). Never writes anything.
# The rules run in this order, the first that gives a result wins:
#   batch (a SEPA payment file we generated) .... 100
#   1 structured communication, same amount ..... 100 (same invoice, other amount: 80); for a supplier invoice: its payment reference
#   2 invoice number in the communication ....... 95  (customer: our number; supplier: the supplier's reference)
#   5 grouped payment (named invoices) .......... 80
#   3 same amount, counterparty IBAN = partner .. 90  (a single candidate)
#   4 same amount, similar name (pg_trgm >= 0.6) . 75  (a single candidate)
#   5 grouped payment (open invoices of one partner adding up to the amount, 10 invoices at most) ... 80
#   6 a bank rule of the entity ................. its own score
#   fees (a debit that says "fee") .............. 75
# A receipt is matched to customer invoices; a payment to supplier invoices (single invoice only: the payment service takes one).
# `confidence` stays :high (90 and more) or :medium for the screens that already read it.
class Accounting::MatchBankTransaction
  # rounding: what the invoice still asked for minus what came in (positive: a few cents short), when within the tolerance.
  Suggestion = Struct.new(:kind, :target, :confidence, :excess, :score, :rule, :rounding, keyword_init: true)

  SIMILARITY = 0.6
  GROUP_LIMIT = 10
  OPEN = %i[posted partially_paid].freeze

  # `open_invoices`: optional preloaded open customer invoices, so a caller matching many transactions queries them once.
  def self.call(transaction:, open_invoices: nil)
    return unless transaction.pending?
    return if transaction.currency != "EUR" # amounts below are EUR: a foreign movement is never matched by amount

    match_batch(transaction) || (transaction.credit? ? match_receipt(transaction, open_invoices) : match_payment(transaction)) ||
      match_rule(transaction) || match_fees(transaction)
  end

  def self.suggestion(kind, target, score, rule, excess: 0, rounding: BigDecimal("0"))
    Suggestion.new(kind: kind, target: target, confidence: score >= 90 ? :high : :medium, excess: excess, score: score, rule: rule, rounding: rounding)
  end

  # The rounding tolerance of the entity (0,05 EUR by default) applies to receipts only, and only once the owner has created the
  # two rounding accounts. => the difference (invoice remaining - amount received) when the amount is the invoice's within the
  # tolerance (0 when it is exactly the invoice's), nil otherwise.
  def self.rounding_for(invoice, received, side)
    remaining = invoice.remaining_amount
    return BigDecimal("0") if remaining == received
    return unless side == :customer && Accounting::CreateRoundingAccounts.ready?

    difference = remaining - received
    difference if difference.abs <= ActsAsTenant.current_tenant.bank_rounding_tolerance
  end

  def self.match_receipt(tx, open_invoices)
    match_invoice(tx) || match_invoice_number(tx, :customer, open_invoices) || match_invoices(tx, open_invoices) || match_by_partner(tx, :customer) || match_group(tx)
  end

  def self.match_payment(tx)
    match_supplier_reference(tx) || match_invoice_number(tx, :supplier) || match_by_partner(tx, :supplier)
  end

  # Rule 1 for a supplier invoice (F06): the structured communication of the payment is the payment reference the supplier gave on the invoice
  # (kept when it was received through Peppol), same amount, only one invoice.
  def self.match_supplier_reference(tx)
    digits = Accounting::StructuredCommunication.extract(tx.structured_communication.presence || tx.description) or return
    found = open_invoices_of(:supplier).where.not(payment_reference: nil).select { |i| Accounting::StructuredCommunication.extract(i.payment_reference) == digits }
    return unless found.size == 1 && (rounding = rounding_for(found.first, tx.amount.abs, :supplier))

    suggestion(:supplier_invoice, found.first, 100, 1, rounding: rounding)
  end

  def self.open_customer_invoices = Accounting::Invoice.customer.invoice.posted.where.not(invoice_number: nil).includes(:credit_notes, :journal, :cash_journal, :credited_invoice, :entity, partner: :entity)

  def self.match_batch(tx)
    return unless tx.debit? && tx.reference.present?

    batch = Accounting::PaymentBatch.where(status: %i[generated executed]).find_by(message_id: tx.reference)
    suggestion(:payment_batch, batch, 100, nil) if batch && batch.total_amount == -tx.amount
  end

  def self.match_invoice(tx)
    return unless tx.credit? && (digits = Accounting::StructuredCommunication.extract(tx.description))

    invoice = Accounting::Invoice.customer.invoice.where(status: OPEN).find_by(id: Accounting::StructuredCommunication.id_from(digits))
    return unless invoice

    rounding = rounding_for(invoice, tx.amount, :customer)
    excess = rounding ? 0 : [ tx.amount - invoice.remaining_amount, 0 ].max
    suggestion(:invoice, invoice, rounding ? 100 : 80, 1, excess: excess, rounding: rounding || BigDecimal("0"))
  end

  # Rule 2: the invoice number (customer) or the supplier's reference (supplier) in the communication, same amount, only one invoice.
  def self.match_invoice_number(tx, side, preloaded = nil)
    return if tx.description.blank?

    field = side == :customer ? :invoice_number : :supplier_reference
    found = (preloaded || open_invoices_of(side).to_a).select do |invoice|
      next false if invoice.public_send(field).blank?

      tx.description.match?(/(?<![\w-])#{Regexp.escape(invoice.public_send(field))}(?![\w-])/)
    end
    return unless found.size == 1 && (rounding = rounding_for(found.first, tx.amount.abs, side))

    suggestion(side == :customer ? :invoice : :supplier_invoice, found.first, 95, 2, rounding: rounding)
  end

  # Rules 3 and 4: the same amount, and the partner known by the counterparty's IBAN (90) or by a similar name (75); one candidate.
  def self.match_by_partner(tx, side)
    [ [ partners_by_iban(tx), 90, 3 ], [ partners_by_name(tx), 75, 4 ] ].each do |partners, score, rule|
      next if partners.empty?

      found = open_invoices_of(side).where(partner_id: partners).filter_map { |invoice| (rounding = rounding_for(invoice, tx.amount.abs, side)) && [ invoice, rounding ] }
      return suggestion(side == :customer ? :invoice : :supplier_invoice, found.first.first, score, rule, rounding: found.first.last) if found.size == 1
    end
    nil
  end

  # Rule 5: open invoices of one partner (ten at most, the oldest first) whose sum is the amount, one combination only.
  def self.match_group(tx)
    solutions = (partners_by_iban(tx).presence || partners_by_name(tx)).flat_map do |partner|
      owed = open_invoices_of(:customer).where(partner_id: partner).order(:due_date, :id).limit(GROUP_LIMIT).to_a.map { |i| [ i, i.remaining_amount ] }.select { |_, amount| amount.positive? }
      next [] if owed.any? { |_, amount| amount == tx.amount } # a single invoice would have matched, or it is ambiguous

      (2..owed.size).flat_map { |size| owed.combination(size).select { |group| group.sum { |_, amount| amount } == tx.amount }.map { |group| group.map(&:first) } }
    end
    suggestion(:invoices, solutions.first.sort_by(&:id), 80, 5) if solutions.size == 1
  end

  def self.open_invoices_of(side)
    scope = Accounting::Invoice.invoice.where(status: OPEN)
    return scope.customer.where.not(invoice_number: nil).includes(:credit_notes) if side == :customer

    # a supplier invoice whose payment waits as a draft is not offered again (a draft receipt already lowers the customer balance)
    scope.supplier.includes(:credit_notes).where.not(id: draft_payment_lines.select(:invoice_id))
  end

  def self.draft_payment_lines
    Accounting::JournalEntryLine.joins(:journal_entry).where(accounting_journal_entries: { status: Accounting::JournalEntry.statuses[:draft] })
                                .where.not(invoice_id: nil).where("accounting_journal_entry_lines.debit > 0")
  end

  def self.draft_payment?(invoice) = draft_payment_lines.exists?(invoice_id: invoice.id)

  def self.partners_by_iban(tx)
    iban = tx.counterparty_iban.to_s.delete(" ").upcase
    iban.empty? ? Accounting::Partner.none : Accounting::Partner.where("upper(replace(iban, ' ', '')) = ?", iban).select(:id)
  end

  def self.partners_by_name(tx)
    return Accounting::Partner.none if tx.counterparty_name.blank?

    Accounting::Partner.where("similarity(lower(f_unaccent(name)), lower(f_unaccent(?))) >= ?", tx.counterparty_name, SIMILARITY).select(:id)
  end

  # Rule 6: a bank rule of the entity (frais bancaires, assurances, loyers...), the first by priority.
  def self.match_rule(tx)
    rule = Accounting::BankRule.first_match_for(tx)
    suggestion(:rule, rule, rule.score, 6) if rule
  end

  # Grouped transfer: several open invoices of one partner named in the description, whose balances add up to the amount.
  # ponytail: scans open customer invoices in Ruby; index/limit by partner if the open-invoice count gets large.
  def self.match_invoices(tx, open_invoices)
    return unless tx.credit? && tx.description.present?

    named = (open_invoices || open_customer_invoices).select do |invoice|
      tx.description.match?(/(?<![\w-])#{Regexp.escape(invoice.invoice_number)}(?![\w-])/)
    end
    return unless named.size > 1 && named.map(&:partner_id).uniq.one? && named.sum(&:remaining_amount) == tx.amount

    suggestion(:invoices, named, 80, 5)
  end

  FEES_ACCOUNT_CODE = Accounting::AccountCodes::BANK_FEES
  FEES_PATTERN      = /\bfees?\b/i

  # A debit mentioning a fee goes to bank fees. ponytail: single keyword and account; make them settings if needed.
  def self.match_fees(tx)
    return unless tx.debit? && tx.description.to_s.match?(FEES_PATTERN)

    account = Accounting::Account.find_by(code: FEES_ACCOUNT_CODE)
    suggestion(:expense, account, 75, nil) if account
  end
  private_class_method :rounding_for, :draft_payment_lines, :match_batch, :match_invoice, :match_invoices, :match_fees, :match_receipt, :match_payment, :match_supplier_reference, :match_invoice_number, :match_by_partner,
                       :match_group, :open_invoices_of, :partners_by_iban, :partners_by_name, :match_rule
end
