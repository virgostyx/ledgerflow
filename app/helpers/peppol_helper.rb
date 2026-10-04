module PeppolHelper
  # May the current user do this with Peppol (index?, resend?, configure?...): Accounting::PeppolMessagePolicy, which pundit's `policy` cannot
  # reach for a record of another class.
  def peppol_allowed?(action) = Accounting::PeppolMessagePolicy.new(current_user, :peppol).public_send(action)

  # The Access Point of the entity is a sandbox or a simulation: the Peppol screens say so.
  def peppol_test_environment?
    entity = ActsAsTenant.current_tenant
    entity&.peppol_access_point.present? && Peppol::AccessPoint.for(entity).test_environment?
  rescue Peppol::AccessPoint::Error
    false
  end

  STATUS_STYLES = { "processed" => "bg-emerald-100 text-emerald-800", "delivered" => "bg-emerald-100 text-emerald-800", "needs_review" => "bg-amber-100 text-amber-800",
                    "failed" => "bg-red-100 text-red-800", "dismissed" => "bg-gray-100 text-gray-600" }.freeze

  def peppol_status_badge(message)
    tag.span(message.status.humanize, class: "text-xs px-2 py-1 rounded-full #{STATUS_STYLES.fetch(message.status, 'bg-gray-100 text-gray-700')}")
  end

  # The XML to read: indented, and the embedded files (base64) replaced by their size, which would bury the document.
  def peppol_xml_for_display(xml)
    doc = Nokogiri::XML(xml.to_s) { |c| c.noblanks }
    doc.xpath("//*[local-name()='EmbeddedDocumentBinaryObject']").each { |node| node.content = "[#{number_to_human_size(node.text.size * 3 / 4)} of base64 not shown]" }
    doc.to_xml(indent: 2).truncate(200_000, omission: "\n… (cut: the whole XML is kept)")
  rescue StandardError
    xml.to_s.truncate(200_000)
  end
end
