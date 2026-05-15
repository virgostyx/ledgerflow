class Accounting::Actions::ComputeInvoiceTotals
  extend LightService::Action

  expects  :invoice
  promises :invoice

  executed do |ctx|
    invoice = ctx.invoice
    invoice.compute_totals
    invoice.save!
    ctx.invoice = invoice
  end
end
