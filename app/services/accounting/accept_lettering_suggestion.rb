# F04: letters the lines of a proposal (a person, or the nightly job with auto: true) and marks it accepted. The lettering goes
# through LetterLines, so every check applies; a proposal that no longer holds is left as it is, with the reason.
class Accounting::AcceptLetteringSuggestion
  def self.call(suggestion:, user:, auto: false)
    ctx = LightService::Context.make(suggestion: suggestion)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.lettering.suggestion_decided")) } unless suggestion.proposed?

    Accounting::LetteringSuggestion.transaction do
      result = Accounting::LetterLines.call(lines: suggestion.lines.to_a, user: user, auto: auto)
      next ctx.fail!(result.message) if result.failure?

      suggestion.update!(status: :accepted, decided_by: user, decided_at: Time.current)
      ctx[:lettering] = result[:lettering]
    end
    ctx
  end
end
