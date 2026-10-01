# A third party (BudgetFlow) takes over a Peppol invoice received in LedgerFlow: the draft becomes the document it addresses by
# its own reference, so that its later PUT fills this same draft in instead of creating a second invoice. The supplier's own
# invoice number moves to supplier_reference (external_ref is the third party's key). A draft only: once the accountant has
# booked or cancelled it, it is theirs. Idempotent for the same reference.
class Accounting::ClaimIncomingInvoice
  Result = Struct.new(:status, :invoice, :errors, keyword_init: true)
  CLAIMED = "claimed" # external_digest of a taken-over draft: no payload has this fingerprint, so the first PUT replaces it

  def self.call(invoice:, external_ref:)
    ref = external_ref.to_s.strip
    return failure(:unprocessable, external_ref: [ "is required" ]) if ref.empty?
    return already_claimed(invoice, ref) if invoice.external_digest.present?
    return failure(:conflict, base: [ "Only a draft can be taken over: the accountant has already booked or cancelled this invoice." ]) unless invoice.draft?

    ApplicationRecord.transaction(requires_new: true) do
      invoice.update!(supplier_reference: invoice.supplier_reference.presence || invoice.external_ref, external_ref: ref,
                      revision: 1, external_digest: CLAIMED)
      invoice.update_columns(external_state_digest: Accounting::ExternalInvoice.state_digest(invoice.reload))
    end
    Result.new(status: :ok, invoice: invoice.reload)
  rescue ActiveRecord::RecordNotUnique
    failure(:conflict, base: [ "This reference is already used by another document." ])
  end

  def self.already_claimed(invoice, ref)
    return Result.new(status: :ok, invoice: invoice) if invoice.external_ref == ref

    failure(:conflict, base: [ "Already taken over under another reference." ])
  end

  def self.failure(status, errors) = Result.new(status: status, errors: errors)
  private_class_method :already_claimed, :failure
end
