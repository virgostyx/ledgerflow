# B03c: what can be said, today, of a certificate that was issued: its signature, what its key says of itself, the chain of anchors up to the anchor it names, and what was
# validated since (a count: no amount, no name). A certificate attests the state at its instant: later entries do not make it false, and are only told.
#
# state: :valid, :signature_invalid (the certificate is not what was signed), :chain_changed (the anchors no longer hold to the one it names), :key_revoked (the key was
# compromised since: the signature is genuine and worth no more than that), :revoked (the issue was a mistake).
module Integrity::VerifyCertificate
  Result = Struct.new(:state, :signature_valid, :key_status, :revoked, :chain_intact, :since, keyword_init: true)

  def self.call(certificate)
    ActsAsTenant.with_tenant(certificate.entity) do
      signature = Ledger::SigningKeys.verify(certificate.key_id, certificate.body, certificate.signature)
      key_status = Ledger::SigningKeys.status_of(certificate.key_id)
      chain = chain_holds?(certificate)
      Result.new(state: state_of(certificate, signature, key_status, chain), signature_valid: signature, key_status: key_status, revoked: certificate.revoked?, chain_intact: chain, since: since(certificate))
    end
  end

  def self.state_of(certificate, signature, key_status, chain)
    return :revoked if certificate.revoked?
    return :signature_invalid unless signature
    return :chain_changed unless chain
    return :key_revoked if key_status == "revoked"

    :valid
  end
  private_class_method :state_of

  # The anchors, up to the one the certificate names, still follow from the entries, and that one still has the hash the certificate gives.
  def self.chain_holds?(certificate)
    anchor = Ledger::Anchor.find_by(number: certificate.anchor_number)
    return false unless anchor && anchor.anchor_hash == certificate.payload.dig("coverage", "anchors", "last_anchor_hash")

    result = Ledger::AnchorChain.verify(certificate.entity)
    result.intact? || result.broken_number > certificate.anchor_number
  end
  private_class_method :chain_holds?

  def self.since(certificate)
    later = Accounting::JournalEntry.where(status: Accounting::JournalEntry.ledger_status_values).where("posted_seq > ?", certificate.through_seq)
    in_period = certificate.fiscal_year_id ? later.where(fiscal_year_id: certificate.fiscal_year_id) : later.where("entry_date <= ?", certificate.covered_at.to_date)
    { entries: later.count, in_period: in_period.count }
  end
  private_class_method :since
end
