# Tells the author that an owner read their conversation with the assistant (A01): who, when, why. Never what was in it.
class Agent::ReviewMailer < ApplicationMailer
  def conversation_read(review)
    @review = review
    @entity = review.entity
    mail(to: review.author.email, subject: "[LedgerFlow] Your assistant conversation was read — #{@entity.legal_name}")
  end
end
