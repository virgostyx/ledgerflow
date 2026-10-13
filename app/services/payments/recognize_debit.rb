# Rule 0 of the bank matching (B01c §6 "Reconnaissance du lot dans le relevé"): which payment batch a debit line of the statement is the debit of. Nothing is written: a
# person confirms what is proposed (Payments::ConfirmDebit), and nothing is ever confirmed by itself.
#   A  a grouped line: the total of the batch, in its window, and the batch says which (its reference or message id is on the line) .... 100
#   A' the same without any reference, when only one batch fits ...................................................................... 90
#   B  the line of one payment: its amount, the account paid, and its end-to-end id or its remittance (100) or nothing more (90, when only one fits)
#   C  the total of the batch less a few payments (five at most; the reference is required; only one set of payments fits): probable rejections .... 70
# The window of a batch runs from a day before its execution date to five open days after (the days its bank profile closes included). The format of what each bank writes for
# a batch is not assumed: where the reference is looked for is every place a CODA line keeps text (communication, bank reference, customer reference, structured communication).
# Two batches that look alike (same total, same window) are never told apart by the amount: only a reference does, and without one nothing is proposed.
# => Proposal(batch, items, missing_items, score, rule, warnings), or nil.
class Payments::RecognizeDebit
  Proposal = Struct.new(:batch, :items, :missing_items, :score, :rule, :warnings, :link, keyword_init: true) # link: the batch was debited by hand, the line only has to be tied to it

  DAYS_BEFORE = 1
  OPEN_DAYS_AFTER = 5
  MAX_MISSING = 5
  MAX_ITEMS_FOR_PARTIAL = 60 # the search for the missing payments is bounded: a bigger batch gets no proposal of this kind

  def self.call(transaction) = new(transaction).call

  def initialize(transaction)
    @tx = transaction
    @amount = -transaction.amount
  end

  def call
    return unless @tx.pending? && @tx.debit? && @tx.currency == "EUR"
    return if batches.empty?

    grouped || single_payment || partial
  end

  private

  def date = @tx.value_date || @tx.transaction_date

  def batches
    @batches ||= Payments::Batch.where(bank_account_id: @tx.bank_account_id, status: %i[exported submitted cancel_requested]).or(by_hand).includes(:bank_profile, items: [])
                                .select { |batch| in_window?(batch) }
  end

  def in_window?(batch)
    first = batch.requested_execution_date - DAYS_BEFORE
    closed = Array(batch.bank_profile&.options&.dig("closed_days"))
    last = batch.requested_execution_date
    OPEN_DAYS_AFTER.times { last = Payments::SettlementCalendar.next_open(last + 1, extra_closed: closed) }
    (first..last).cover?(date)
  end

  # A batch debited by hand waits for its line: its payments are the confirmed ones that no line is tied to yet.
  def by_hand = Payments::Batch.where(bank_account_id: @tx.bank_account_id, status: :debited, debit_kind: "manual")

  def open_items(batch) = batch.debited? ? batch.items.select { |item| item.confirmed? && item.bank_transaction_id.nil? } : batch.items.select(&:included?)

  def text = @text ||= [ @tx.description, @tx.reference, @tx.bank_reference, @tx.structured_communication, *@tx.raw_data.to_h.values_at("customer_reference", "communication") ].compact.join(" ").upcase

  def mentions?(token) = token.present? && text.match?(/(?<![A-Z0-9])#{Regexp.escape(token.upcase)}(?!\d)/)

  def names?(batch) = mentions?(batch.reference) || mentions?(batch.message_id)

  def warnings(batch) = batch.cancel_requested? ? [ :cancel_requested ] : []

  def proposal(batch, items, score, rule, missing: []) = Proposal.new(batch: batch, items: items, missing_items: missing, score: score, rule: rule, warnings: warnings(batch), link: batch.debited?)

  # A, A'
  def grouped
    fitting = batches.select { |batch| open_items(batch).sum(&:amount) == @amount && open_items(batch).any? }
    named = fitting.select { |batch| names?(batch) }
    return proposal(named.first, open_items(named.first), 100, "A") if named.one?
    return if named.any? || fitting.size != 1 # two references on one line, or two batches that look alike: a person chooses

    proposal(fitting.first, open_items(fitting.first), 90, "A'") if batches.none? { |batch| names?(batch) && batch != fitting.first } # a line that names another batch is not this one
  end

  # B
  def single_payment
    iban = @tx.counterparty_iban.to_s.delete(" ").upcase
    return if iban.blank?

    found = batches.flat_map { |batch| open_items(batch).select { |item| item.amount == @amount && item.iban.to_s.delete(" ").upcase == iban }.map { |item| [ batch, item ] } }
    return if found.empty?

    identified = found.select { |_batch, item| mentions?(item.end_to_end_id) || remitted?(item) }
    return proposal(*identified.first.then { |batch, item| [ batch, [ item ] ] }, 100, "B") if identified.one?
    return if identified.any? || found.size != 1

    batch, item = found.first
    proposal(batch, [ item ], 90, "B")
  end

  # The remittance of the payment on the line: a structured communication by its digits, a free one as written.
  def remitted?(item)
    return false if item.remittance.blank?

    digits = item.structured_remittance ? item.remittance.to_s.delete("^0-9") : nil
    digits.present? ? text.delete("^0-9").include?(digits) : text.include?(item.remittance.upcase)
  end

  # C
  def partial
    named = batches.select { |batch| names?(batch) }
    return unless named.one?

    batch = named.first
    items = open_items(batch)
    gap = items.sum(&:amount) - @amount
    return unless gap.positive? && items.size <= MAX_ITEMS_FOR_PARTIAL

    sets = missing_sets(items, gap)
    return unless sets.size == 1

    missing = sets.first
    proposal(batch, items - missing, 70, "C", missing: missing)
  end

  # The sets of at most MAX_MISSING payments that add up to `gap`; two are enough to know the answer is not unique.
  def missing_sets(items, gap)
    ordered = items.sort_by { |item| -item.amount }
    found = []
    search = lambda do |from, chosen, left|
      return found << chosen if left.zero? && chosen.any?
      return if found.size > 1 || chosen.size == MAX_MISSING || left.negative?

      (from...ordered.size).each do |i|
        break if found.size > 1

        search.call(i + 1, chosen + [ ordered[i] ], left - ordered[i].amount) if ordered[i].amount <= left
      end
    end
    search.call(0, [], gap)
    found
  end
end
