require "rails_helper"

RSpec.describe Accounting::ExtractDocument do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:invoice_text) do
    "ACME Consulting SPRL\nVAT BE0123456749\nInvoice No: INV-2026-0042\nInvoice date: 12/03/2026\nDue date: 11/04/2026\n" \
      "Total excl. VAT 1.000,00 EUR\nVAT 21% 210,00 EUR\nTotal incl. VAT 1.210,00 EUR\nIBAN BE68 5390 0754 7034"
  end

  def store(content, filename)
    Accounting::UploadDocument.call(io: StringIO.new(content), filename: filename, user: user)[:document]
  end

  def invoice_pdf = Prawn::Document.new { |pdf| invoice_text.each_line { |line| pdf.text line.chomp } }.render

  def extraction(document) = document.reload.extracted_data["extraction"]

  def proposed(document, name) = extraction(document).dig("fields", name, "value")

  describe "a PDF with a text layer" do
    let(:document) { store(invoice_pdf, "invoice.pdf") }

    it "proposes the fields, from the text layer, and says so" do
      described_class.call(document: document)

      expect(extraction(document)).to include("status" => "done", "method" => "text_layer", "confidence" => 100)
      expect(proposed(document, "invoice_number")).to eq("INV-2026-0042")
      expect(proposed(document, "total")).to eq("1210.00")
      expect(proposed(document, "iban")).to eq("BE68539007547034")
    end

    it "keeps for each proposal where it came from, and that nobody confirmed it yet" do
      described_class.call(document: document)

      field = extraction(document).dig("fields", "total")
      expect(field).to include("snippet" => a_string_including("1.210,00"), "page" => 1, "confirmed" => false)
    end

    it "keeps the text, so that the document can be searched" do
      described_class.call(document: document)

      expect(document.reload.search_text).to include("INV-2026-0042", "ACME Consulting")
    end

    it "never creates an entry nor changes the document's kind: it proposes" do
      expect { described_class.call(document: document) }.not_to change { [ Accounting::JournalEntry.count, Accounting::Invoice.count, document.reload.kind ] }
    end

    it "gives the same result when run again" do
      described_class.call(document: document)
      first = extraction(document).except("extracted_at")

      described_class.call(document: document)

      expect(extraction(document).except("extracted_at")).to eq(first)
    end

    it "is a success the caller can test" do
      expect(described_class.call(document: document)).to be_success
    end
  end

  describe "fields a person already confirmed" do
    let(:document) { store(invoice_pdf, "invoice.pdf") }

    it "are never overwritten by a new extraction, the others are refreshed" do
      described_class.call(document: document)
      data = document.reload.extracted_data
      data["extraction"]["fields"]["total"].merge!("value" => "1200.00", "confirmed" => true)
      data["extraction"]["fields"]["invoice_number"]["value"] = "WRONG"
      document.update_columns(extracted_data: data)

      described_class.call(document: document)

      expect(proposed(document, "total")).to eq("1200.00")
      expect(proposed(document, "invoice_number")).to eq("INV-2026-0042")
    end
  end

  describe "a scan" do
    before { skip "tesseract and poppler are not installed here" unless ocr_tools_available? }

    it "is read by OCR when the PDF has no text layer" do
      document = store(sample_scanned_pdf(invoice_text.lines.first(4).join), "scan.pdf")

      described_class.call(document: document)

      expect(extraction(document)).to include("status" => "done", "method" => "ocr")
      expect(extraction(document)["confidence"]).to be >= Accounting::Extractors::Ocr::MIN_CONFIDENCE
      expect(proposed(document, "invoice_number")).to eq("INV-2026-0042")
    end

    it "is read by OCR when it is a picture" do
      png = render_pdf_to_png(invoice_pdf, resolution: 200)
      document = store(png, "photo.png")

      described_class.call(document: document)

      expect(extraction(document)["method"]).to eq("ocr")
      expect(proposed(document, "total")).to eq("1210.00")
    end

    it "proposes nothing when the picture cannot be read with confidence" do
      noise = Dir.mktmpdir do |dir|
        path = File.join(dir, "n.png")
        system("convert", "-size", "600x400", "xc:gray50", "+noise", "Random", path, exception: true)
        File.binread(path)
      end
      document = store(noise, "noise.png")

      described_class.call(document: document)

      expect(extraction(document)).to include("status" => "low_confidence")
      expect(extraction(document)["fields"]).to be_blank
      expect(document.reload.search_text).to be_blank
    end
  end

  describe "an invoice in UBL" do
    it "is read directly, with the supplier recognised" do
      partner = create(:partner, :supplier, vat_number: "BE0123456749")
      document = store(sample_full_ubl, "invoice.xml")

      described_class.call(document: document)

      expect(extraction(document)).to include("status" => "done", "method" => "ubl", "confidence" => 100)
      expect(proposed(document, "supplier_partner_id")).to eq(partner.id)
      expect(proposed(document, "total")).to eq("1210.00")
    end

    it "has nothing to read in an XML that is not an invoice" do
      document = store("<Order><ID>1</ID></Order>", "order.xml")

      described_class.call(document: document)

      expect(extraction(document)).to include("status" => "not_applicable")
    end
  end

  describe "what is not read" do
    it "leaves a password-protected PDF alone, marked unreadable" do
      document = store(sample_encrypted_pdf, "locked.pdf")

      described_class.call(document: document)

      expect(extraction(document)).to include("status" => "unreadable")
      expect(extraction(document)["fields"]).to be_blank
    end

    it "has nothing to read in a spreadsheet or a CSV" do
      [ [ sample_xlsx, "book.xlsx" ], [ sample_csv, "data.csv" ] ].each do |content, name|
        document = store(content, name)

        described_class.call(document: document)

        expect(extraction(document)).to include("status" => "not_applicable")
      end
    end
  end

  describe "when something goes wrong" do
    let(:document) { store(invoice_pdf, "invoice.pdf") }

    it "records the failure on the document, then raises so that the job can retry" do
      allow(Accounting::Extractors::PdfText).to receive(:call).and_raise(RuntimeError, "disk on fire")

      expect { described_class.call(document: document) }.to raise_error(RuntimeError, "disk on fire")

      expect(extraction(document)).to include("status" => "failed", "error" => "disk on fire")
    end

    it "does not touch the file nor its checksum" do
      before = document.sha256
      described_class.call(document: document)

      expect(document.reload.sha256).to eq(before)
      expect(document.file.download).to eq(invoice_pdf.b.then { document.file.download })
    end
  end

  describe "a document already linked to a validated entry" do
    it "still gets its proposals (derived data), though its file and details stay frozen" do
      document = store(invoice_pdf, "invoice.pdf")
      Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted), user: user)

      expect { described_class.call(document: document) }.not_to raise_error

      expect(proposed(document, "invoice_number")).to eq("INV-2026-0042")
    end
  end

  describe "other entities" do
    it "never reads the partners of another entity to name a supplier" do
      ActsAsTenant.with_tenant(create(:entity)) { create(:partner, :supplier, vat_number: "BE0123456749") }
      document = store(invoice_pdf, "invoice.pdf")

      described_class.call(document: document)

      expect(extraction(document)["fields"]).not_to have_key("supplier_partner_id")
    end
  end
end
