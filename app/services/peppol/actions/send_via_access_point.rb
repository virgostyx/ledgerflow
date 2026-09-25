class Peppol::Actions::SendViaAccessPoint
  extend LightService::Action

  expects  :invoice, :ubl_xml, :access_point, :sender, :receiver
  promises :peppol_id

  executed do |ctx|
    ctx.peppol_id = ctx.access_point.send_document(xml: ctx.ubl_xml, sender: ctx.sender, receiver: ctx.receiver,
                                                   document_id: ctx.invoice.invoice_number)
  rescue Peppol::AccessPoint::Error => e
    ctx.fail!(e.message)
  end
end
