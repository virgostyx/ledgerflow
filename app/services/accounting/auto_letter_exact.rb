# F04: for an entity that asked for it (auto_reconcile_exact), letters by itself the suggestions of score 100 and nothing else.
# Each lettering is marked automatic, audited with the rule and the lines, and undone like any other. => number lettered
class Accounting::AutoLetterExact
  SCORE = Accounting::LetteringSuggestion::SCORES.fetch(1)

  def self.call
    return 0 unless ActsAsTenant.current_tenant.auto_reconcile_exact?

    Accounting::LetteringSuggestion.proposed.where(score: SCORE).count do |suggestion|
      result = Accounting::AcceptLetteringSuggestion.call(suggestion: suggestion, user: nil, auto: true)
      next false if result.failure?

      Accounting::AuditLog.record!(auditable: result[:lettering], action: "auto_lettering", user: nil,
                                   payload: { suggestion_id: suggestion.id, rule: suggestion.rule, score: suggestion.score, line_ids: suggestion.line_ids })
      true
    end
  end
end
