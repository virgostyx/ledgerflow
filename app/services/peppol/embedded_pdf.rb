# The PDF a supplier embedded in its UBL (AdditionalDocumentReference/Attachment/EmbeddedDocumentBinaryObject): the first file that really is a PDF
# (declared as one, starts with %PDF, within the size limit). => { bytes:, filename: } or nil. Used to keep it on the invoice and to show it.
module Peppol::EmbeddedPdf
  MAX_BYTES = 15.megabytes

  def self.find(xml)
    doc = xml.is_a?(Nokogiri::XML::Document) ? xml : Nokogiri::XML(xml.to_s).tap(&:remove_namespaces!)
    doc.xpath("//AdditionalDocumentReference/Attachment/EmbeddedDocumentBinaryObject").each do |node|
      next unless node["mimeCode"].to_s.casecmp?("application/pdf")

      bytes = Base64.decode64(node.text.to_s)
      return { bytes: bytes, filename: node["filename"].presence } if bytes.start_with?("%PDF") && bytes.bytesize <= MAX_BYTES
    end
    nil
  end
end
