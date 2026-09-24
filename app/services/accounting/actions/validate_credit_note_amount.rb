# A credit note linked to an invoice may not push the credited total above that invoice's total.
class Accounting::Actions::ValidateCreditNoteAmount
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice  = ctx.invoice
    original = invoice.credited_invoice
    next unless invoice.credit_note? && original

    already = original.credit_notes.where(status: %i[posted partially_paid paid]).where.not(id: invoice.id).sum(:total_incl_vat)
    ctx.fail_with_rollback!(I18n.t("accounting.invoices.errors.credit_exceeds_invoice")) if already + invoice.total_incl_vat > original.total_incl_vat
  end
end
