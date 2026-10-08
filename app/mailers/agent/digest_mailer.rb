# The e-mail of a summary (A10a): counts and links, no amount and no name, unless the entity allowed details. Nothing of the books is in an e-mail by default.
class Agent::DigestMailer < ApplicationMailer
  def summary(digest, details: false)
    @digest = digest
    @details = details
    @url = agent_digest_url(digest)
    mail(to: digest.user.email, subject: "[LedgerFlow] #{digest.kind == 'event' ? 'An alert' : 'Your summary'} — #{digest.entity.legal_name}")
  end
end
