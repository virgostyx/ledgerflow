class Accounting::Actions::UpdateInvoiceStatus
  extend LightService::Action

  expects  :invoice
  promises :invoice

  executed do |ctx|
    invoice = ctx.invoice
    invoice.post!
    ctx.invoice = invoice
  end
end
