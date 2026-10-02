# Real file contents for the document specs (F03): what is detected by content must be a real file.
module DocumentFiles
  # A one-page PDF with a text layer, different for each text.
  def sample_pdf(text = "Invoice 2026-001") = Prawn::Document.new { |pdf| pdf.text text }.render

  # A PDF with several pages, one text per page.
  def sample_multipage_pdf(*texts)
    Prawn::Document.new do |pdf|
      texts.each_with_index { |text, i| pdf.start_new_page if i.positive?; pdf.text text }
    end.render
  end

  # 1x1 PNG, with a comment so that two samples can differ.
  def sample_png(tag = "a")
    png = "\x89PNG\r\n\x1a\n".b
    chunk = lambda do |type, data|
      [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
    end
    png + chunk.call("IHDR", [ 1, 1, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) + chunk.call("tEXt", "Comment\0#{tag}") +
      chunk.call("IDAT", Zlib::Deflate.deflate("\0\xff\xff\xff".b)) + chunk.call("IEND", "")
  end

  # A minimal valid JPEG (1x1), closed by the end-of-image marker.
  def sample_jpeg
    Base64.decode64("/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=") + "\xFF\xD9".b
  end

  def sample_tiff = "II*\x00\x08\x00\x00\x00\x00\x00".b

  # A PDF that asks for a password before it can be read.
  def sample_encrypted_pdf = Prawn::Document.new { |pdf| pdf.encrypt_document(user_password: "secret", owner_password: "owner"); pdf.text "hidden" }.render

  def sample_xlsx
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "S") { |sheet| sheet.add_row [ "a", 1 ] }
    package.to_stream.read
  end

  def sample_csv(rows = [ %w[date amount], %w[2026-01-01 10.00] ]) = rows.map { |row| row.join(";") }.join("\n") + "\n"

  def sample_ubl(number = "INV-1")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>#{number}</cbc:ID>
      </Invoice>
    XML
  end

  # A real UBL BIS Billing 3.0 invoice: supplier, dates, payment means (IBAN, structured communication) and totals.
  def sample_full_ubl(number: "UBL-2026-9", vat: "BE0123456749", iban: "BE68539007547034", communication: nil, root: "Invoice")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <#{root} xmlns="urn:oasis:names:specification:ubl:schema:xsd:#{root}-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        <cbc:ID>#{number}</cbc:ID>
        <cbc:IssueDate>2026-03-12</cbc:IssueDate>
        <cbc:DueDate>2026-04-11</cbc:DueDate>
        <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
        <cac:AccountingSupplierParty><cac:Party>
          <cac:PartyName><cbc:Name>ACME Consulting</cbc:Name></cac:PartyName>
          <cac:PartyTaxScheme><cbc:CompanyID>#{vat}</cbc:CompanyID></cac:PartyTaxScheme>
        </cac:Party></cac:AccountingSupplierParty>
        <cac:PaymentMeans>
          <cbc:PaymentMeansCode>30</cbc:PaymentMeansCode>
          #{communication ? "<cbc:PaymentID>#{communication}</cbc:PaymentID>" : ""}
          <cac:PayeeFinancialAccount><cbc:ID>#{iban}</cbc:ID></cac:PayeeFinancialAccount>
        </cac:PaymentMeans>
        <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">210.00</cbc:TaxAmount></cac:TaxTotal>
        <cac:LegalMonetaryTotal>
          <cbc:TaxExclusiveAmount currencyID="EUR">1000.00</cbc:TaxExclusiveAmount>
          <cbc:TaxInclusiveAmount currencyID="EUR">1210.00</cbc:TaxInclusiveAmount>
          <cbc:PayableAmount currencyID="EUR">1210.00</cbc:PayableAmount>
        </cac:LegalMonetaryTotal>
      </#{root}>
    XML
  end

  def ocr_tools_available? = %w[tesseract pdftoppm].all? { |tool| system("which", tool, out: File::NULL, err: File::NULL) }

  # A scan: the pages of a PDF turned into pictures (poppler), so there is no text layer left.
  def render_pdf_to_png(pdf_bytes, resolution: 150)
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "in.pdf"), pdf_bytes)
      system("pdftoppm", "-png", "-r", resolution.to_s, "-f", "1", "-l", "1", File.join(dir, "in.pdf"), File.join(dir, "page"), exception: true)
      File.binread(Dir[File.join(dir, "page*.png")].min)
    end
  end

  # A PDF that holds only a picture: no text layer, what a scanner produces.
  def sample_scanned_pdf(text)
    png = render_pdf_to_png(Prawn::Document.new { |pdf| pdf.text text, size: 28 }.render)
    Prawn::Document.new { |pdf| pdf.image StringIO.new(png), fit: [ 500, 700 ] }.render
  end

  def sample_exe = "MZ\x90\x00\x03\x00\x00\x00".b + ("\x00" * 200)

  def upload_io(content, filename) = { io: StringIO.new(content), filename: filename }
end

RSpec.configure { |config| config.include DocumentFiles }
