class Peppol::Actions::BuildUblXml
  extend LightService::Action

  expects :invoice
  promises :ubl_xml

  executed do |ctx|
    ctx.ubl_xml = Peppol::UblInvoiceBuilder.new(ctx.invoice, pdf: Accounting::InvoicePdf.new(ctx.invoice).render).build
  rescue StandardError => e
    ctx.fail!("UBL build error: #{e.message}")
  end
end
