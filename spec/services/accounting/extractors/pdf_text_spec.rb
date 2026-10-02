require "rails_helper"

RSpec.describe Accounting::Extractors::PdfText do
  it "reads the text layer, page after page (separated by a form feed)" do
    bytes = sample_multipage_pdf("Invoice No: A-1 total 100,00 EUR", "Second page: terms and conditions apply here")

    result = described_class.call(bytes)

    expect(result.method).to eq("text_layer")
    pages = result.text.split("\f")
    expect(pages.size).to eq(2)
    expect(pages[0]).to include("Invoice No: A-1")
    expect(pages[1]).to include("terms and conditions")
  end

  it "is sure of what it read" do
    expect(described_class.call(sample_pdf("A text layer with enough words to be a real document")).confidence).to eq(100)
  end

  it "finds no text in a PDF that only holds a picture, so that the scan can be read by OCR instead" do
    skip "needs poppler" unless ocr_tools_available?

    result = described_class.call(sample_scanned_pdf("scanned"))

    expect(result.text.strip).to be_empty
    expect(result.confidence).to be_nil
  end

  it "does not read a password-protected PDF" do
    expect { described_class.call(sample_encrypted_pdf) }.to raise_error(Accounting::Extractors::Unreadable)
  end
end
