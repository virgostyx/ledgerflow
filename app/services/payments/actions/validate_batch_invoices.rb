class Payments::Actions::ValidateBatchInvoices
  extend LightService::Action

  expects :invoice_ids
  promises :invoices

  executed do |ctx|
    invoices = Accounting::Invoice.where(id: ctx.invoice_ids).to_a

    if invoices.empty?
      ctx.fail!(I18n.t("payments.errors.no_invoices_selected"))
      next
    end

    problems = invoices.flat_map { |invoice| eligibility_problems(invoice) }

    if problems.any?
      ctx.fail!(problems.join(" "))
    else
      ctx.invoices = invoices
    end
  end

  def self.eligibility_problems(invoice)
    problems = []

    unless invoice.supplier? && invoice.posted?
      problems << I18n.t("payments.errors.invoice_not_eligible", number: invoice.invoice_number || invoice.id)
    end

    unless invoice.partner.sepa_payable?
      problems << I18n.t("payments.errors.missing_iban", name: invoice.partner.name)
    end

    if Accounting::PaymentBatchLine.active.where(invoice_id: invoice.id).exists?
      problems << I18n.t("payments.errors.already_in_batch", number: invoice.invoice_number || invoice.id)
    end

    problems
  end
end
