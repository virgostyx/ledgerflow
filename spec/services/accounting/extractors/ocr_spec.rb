require "rails_helper"

RSpec.describe Accounting::Extractors::Ocr do
  before { skip "tesseract and poppler are not installed here" unless ocr_tools_available? }

  let(:text) { "INVOICE TOTAL 1210 EUR" }

  it "reads the text of a picture, and says how sure it is" do
    png = render_pdf_to_png(Prawn::Document.new { |pdf| pdf.text text, size: 36 }.render, resolution: 200)

    result = described_class.call(png, "image/png")

    expect(result.method).to eq("ocr")
    expect(result.text.upcase).to include("INVOICE")
    expect(result.confidence).to be >= Accounting::Extractors::Ocr::MIN_CONFIDENCE
  end

  it "reads a scanned PDF (a PDF that only holds a picture)" do
    result = described_class.call(sample_scanned_pdf(text), "application/pdf")

    expect(result.text.upcase).to include("INVOICE")
    expect(result.confidence).to be >= Accounting::Extractors::Ocr::MIN_CONFIDENCE
  end

  it "is not sure of noise: low confidence, nothing worth keeping" do
    noise = Dir.mktmpdir do |dir|
      path = File.join(dir, "n.png")
      system("convert", "-size", "400x200", "xc:gray50", "+noise", "Random", path, exception: true)
      File.binread(path)
    end

    result = described_class.call(noise, "image/png")

    expect(result.confidence.to_i).to be < Accounting::Extractors::Ocr::MIN_CONFIDENCE
  end

  it "reads in the languages that are installed among French, Dutch and English" do
    expect(described_class.languages).to all(satisfy { |lang| %w[fra nld eng].include?(lang) })
    expect(described_class.languages).not_to be_empty
  end

  it "fails with a clear error on something that is not a picture" do
    expect { described_class.call("not an image", "image/png") }.to raise_error(Accounting::Extractors::Unreadable)
  end
end
