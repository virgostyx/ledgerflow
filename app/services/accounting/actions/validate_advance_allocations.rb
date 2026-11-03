# The advances an invoice settles add up to no more than its total, and every one of them is still posted (a draft handed over by the API may wait).
class Accounting::Actions::ValidateAdvanceAllocations
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice
    next if invoice.advance_allocations.empty?

    error = if invoice.advance_allocations.sum(&:amount) > invoice.total_incl_vat       then "accounting.invoices.errors.advances_exceed_invoice"
    elsif invoice.advance_allocations.any? { |a| !a.advance.issued? }                   then "accounting.invoices.errors.advance_not_posted"
    end
    ctx.fail_with_rollback!(I18n.t(error)) if error
  end
end
