# F04: letters the lines of a proposal (a person, or the nightly job with auto: true) and marks it accepted. The lettering goes
# through LetterLines, so every check applies; a proposal that no longer holds is left as it is, with the reason.
class Accounting::AcceptLetteringSuggestion
  def self.call(suggestion:, user:, auto: false)
    ctx = LightService::Context.make(suggestion: suggestion)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.lettering.suggestion_decided")) } unless suggestion.proposed?

    Accounting::LetteringSuggestion.transaction do
      lines = suggestion.lines.to_a
      # a rounding difference is booked by a draft entry first: the lines are lettered when it is validated
      result = suggestion.rule == 6 ? Accounting::WriteOffLettering.call(lines: lines, user: user) : Accounting::LetterLines.call(lines: lines, user: user, auto: auto)
      next ctx.fail!(result.message) if result.failure?

      suggestion.update!(status: :accepted, decided_by: user, decided_at: Time.current)
      ctx[:lettering] = result[:lettering]
      ctx[:entry] = result[:entry]
    end
    ctx
  end
end
