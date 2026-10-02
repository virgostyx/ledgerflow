require "pdf/reader"

# Reads back what a PDF really draws: the strings of its show-text operators, page by page. (The page layout
# pdf-reader builds merges letters that touch other text, so a diagonal watermark is not reliably a "run".)
module PdfWatermarkHelper
  class ShowTextReceiver
    attr_reader :strings

    def initialize = @strings = []
    def show_text(string) = @strings << string
    def show_text_with_positioning(parts) = @strings << parts.grep(String).join
  end

  def pdf_page_strings(bytes)
    PDF::Reader.new(StringIO.new(bytes)).pages.map do |page|
      ShowTextReceiver.new.tap { |receiver| page.walk(receiver) }.strings.map { |s| s.dup.force_encoding("Windows-1252").encode("UTF-8", invalid: :replace, undef: :replace) }
    end
  end

  # What the exporter draws for a name: Windows-1252 only (anything else becomes "?").
  def drawn_form(name) = name.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").encode("UTF-8")

  def watermarked_on_every_page?(bytes, name) = pdf_page_strings(bytes).all? { |strings| strings.include?(drawn_form(name)) }

  def watermarked_on_no_page?(bytes, name) = pdf_page_strings(bytes).none? { |strings| strings.include?(drawn_form(name)) }
end

RSpec.configure { |config| config.include PdfWatermarkHelper }
