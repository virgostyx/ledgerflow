# B03c: the certificate to be read: who it is for, what it covers, the reservations first, what it proves and what it does not (in clear, on every certificate), the key, and the
# address and QR code to verify it. Built from the signed certificate only (nothing is recomputed here).
module Integrity::CertificatePdf
  def self.call(certificate, base_url: nil)
    doc = certificate.payload_hash
    url = "#{base_url}#{doc['verification_path']}"
    Prawn::Document.new(page_size: "A4", margin: 40, info: { Title: "Integrity certificate #{doc['id']}" }) do |pdf|
      pdf.font "Helvetica"
      pdf.text "Integrity certificate", size: 20, style: :bold
      pdf.text "#{doc['company']['name']} - covers the books up to #{doc['covered_at']}", size: 11
      pdf.text "Level: #{doc['disclosure']}#{" - for #{doc['recipient']}" if doc['recipient']}. Issued #{doc['issued_at']}. Certificate #{doc['id']}.", size: 9, color: "555555"
      pdf.move_down 10
      section(pdf, "Reservations", doc["reservations"].presence || [ "None." ])
      pdf.table([ [ "It proves", "It does not prove" ], [ doc["proves"].map { |t| "- #{t}" }.join("\n"), doc["does_not_prove"].map { |t| "- #{t}" }.join("\n") ] ], width: pdf.bounds.width, cell_style: { size: 8, padding: 4 }) do
        row(0).font_style = :bold
        row(0).background_color = "EEEEEE"
      end
      pdf.move_down 10
      coverage = doc["coverage"]
      section(pdf, "Coverage", [ "Entries validated up to place #{coverage['through_seq']}: #{coverage['entries']}#{", lines: #{coverage['lines']}" if coverage['lines']}",
                                 "Anchors #{coverage['anchors']['from']} to #{coverage['anchors']['to']}, last anchor hash #{coverage['anchors']['last_anchor_hash']}",
                                 ("Total debit #{doc['totals']['debit']} = total credit #{doc['totals']['credit']}" if doc["totals"]), "Timestamp: #{doc['timestamp']['status']}" ].compact)
      section(pdf, "Invariants", doc["invariants"].map { |id, r| "#{id}: #{r['status'].tr('_', ' ')}" })
      section(pdf, "Key", [ "#{doc['public_key']['algorithm']} key #{doc['public_key']['key_id']}", "Fingerprint #{doc['public_key']['fingerprint']}", "Compare this fingerprint with the one the issuer gives you by another channel." ])
      pdf.move_down 6
      pdf.text "Verify: #{url}", size: 9
      draw_qr(pdf, url)
    end.render
  end

  # The QR code of the address, drawn square by square (no image library).
  def self.draw_qr(pdf, url)
    size = 2.4
    top = pdf.cursor
    RQRCode::QRCode.new(url).modules.each_with_index do |row, y|
      row.each_with_index { |dark, x| pdf.fill_rectangle([ x * size, top - y * size ], size, size) if dark }
    end
  end
  private_class_method :draw_qr

  def self.section(pdf, title, lines)
    pdf.text title, size: 11, style: :bold
    lines.each { |line| pdf.text line.to_s, size: 8 }
    pdf.move_down 8
  end
  private_class_method :section
end
