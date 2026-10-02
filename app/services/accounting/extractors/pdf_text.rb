# The text layer of a PDF, page after page (pages separated by a form feed). A PDF that only holds a picture has no
# text layer: the result is blank and the caller falls back to OCR.
class Accounting::Extractors::PdfText
  MIN_CHARACTERS = 20

  def self.call(bytes)
    text = PDF::Reader.new(StringIO.new(bytes)).pages.map(&:text).join("\f")
    Accounting::Extractors::Result.new(text: text, method: "text_layer", confidence: text.gsub(/\s/, "").length >= MIN_CHARACTERS ? 100 : nil)
  rescue PDF::Reader::EncryptedPDFError, PDF::Reader::UnsupportedFeatureError
    raise Accounting::Extractors::Unreadable, "password protected"
  rescue StandardError => e
    raise Accounting::Extractors::Unreadable, "unreadable PDF: #{e.class}"
  end
end
