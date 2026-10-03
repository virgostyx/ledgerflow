# Runs the matching engine on pending bank lines (F02) and acts on what it finds:
#  - an exact match on a customer invoice (score 100) is booked as a DRAFT payment entry (validated at once only when the entity
#    has `auto_post_exact_bank_matches`);
#  - a bank rule that asks for it ("book_draft") is booked as a draft too;
#  - 75 and above otherwise: the suggestion is kept in `match_data`, for a person to confirm;
#  - below, or nothing: the line is left alone (and an old suggestion that no longer holds is forgotten).
# One line that cannot be booked is reported and never stops the others. => ctx[:drafted], [:suggested], [:untouched], [:problems]
class Banking::AutoMatch
  MIN_SCORE = 75

  def self.call(transactions:) = new(transactions).call

  def initialize(transactions)
    @transactions = Array(transactions)
    @ctx = LightService::Context.make(drafted: 0, suggested: 0, untouched: 0, transfers: 0, problems: [])
  end

  def call
    pair_transfers
    @transactions.each do |transaction|
      next unless transaction.pending?

      handle(transaction)
    rescue StandardError => e
      @ctx[:problems] << "#{transaction.id}: #{e.message}"
    end
    @ctx
  end

  private

  # The two halves of a transfer between the entity's own accounts, before anything else looks at them.
  def pair_transfers
    @ctx[:transfers] = Banking::InternalTransfers.call(transactions: @transactions)
  rescue StandardError => e
    @ctx[:problems] << "transfers: #{e.message}"
  end

  def handle(transaction)
    suggestion = Accounting::MatchBankTransaction.call(transaction: transaction)
    return leave(transaction) unless suggestion && suggestion.score >= MIN_SCORE
    return book_draft(transaction, suggestion) if book_automatically?(suggestion)

    transaction.update!(match_data: describe(suggestion))
    @ctx[:suggested] += 1
  end

  def book_automatically?(suggestion)
    (suggestion.kind == :invoice && suggestion.score == 100) || (suggestion.kind == :rule && suggestion.target.book_draft?)
  end

  def book_draft(transaction, suggestion)
    result = Accounting::AcceptBankSuggestion.call(transaction: transaction, draft: true)
    return problem(transaction, result&.message) if result.nil? || result.failure?

    transaction.reload.update!(match_data: describe(suggestion).merge("auto" => true))
    Accounting::AuditLog.record!(auditable: transaction, action: "bank_match_auto", payload: { rule: suggestion.rule, score: suggestion.score, kind: suggestion.kind.to_s })
    post(transaction) if ActsAsTenant.current_tenant.auto_post_exact_bank_matches? && suggestion.kind == :invoice
    @ctx[:drafted] += 1
  end

  # The entity asked for its exact matches to be validated: the usual validation, so the line and the invoice settle.
  def post(transaction)
    posted = Accounting::PostJournalEntry.call(entry: transaction.journal_entry)
    @ctx[:problems] << "#{transaction.id}: #{posted.message}" if posted.failure?
  end

  def leave(transaction)
    transaction.update!(match_data: {}) if transaction.match_data.present?
    @ctx[:untouched] += 1
  end

  def problem(transaction, message)
    @ctx[:problems] << "#{transaction.id}: #{message}"
  end

  def describe(suggestion)
    target = suggestion.target
    data = { "kind" => suggestion.kind.to_s, "score" => suggestion.score, "rule" => suggestion.rule }
    case target
    when Array then data.merge("target_ids" => target.map(&:id))
    when nil then data
    else data.merge("target_id" => target.id)
    end
  end
end
