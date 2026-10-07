# Reads the text of a file given to the knowledge base (A06): PDF, DOCX, HTML, Markdown or plain text. The type comes from the bytes, never from the name; nothing is executed or fetched; an XML that
# declares entities is refused. Titles are kept as Markdown headings ("## 2.1 Title") so that the chunker can attach each passage to its section.
# Raises Knowledge::Extract::Refused with a reason: :empty, :unsupported_type, :unsafe_xml, :unreadable.
module Knowledge::Extract
  class Refused < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason.to_s)
    end
  end

  MAX_UNPACKED = 20.megabytes

  def self.call(bytes)
    bytes = bytes.to_s.b
    raise Refused, :empty if bytes.strip.empty?

    if bytes.start_with?("%PDF") then pdf(bytes)
    elsif bytes.start_with?("PK\x03\x04".b) then docx(bytes)
    else text(bytes)
    end
  end

  def self.pdf(bytes)
    reader = PDF::Reader.new(StringIO.new(bytes))
    reader.pages.map(&:text).join("\n\n").presence || raise(Refused, :unreadable)
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, PDF::Reader::EncryptedPDFError
    raise Refused, :unreadable
  end

  def self.docx(bytes)
    require "zip"
    xml = nil
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      entry = zip.find_entry("word/document.xml") or raise Refused, :unsupported_type
      raise Refused, :unreadable if entry.size > MAX_UNPACKED

      xml = entry.get_input_stream.read
    end
    raise Refused, :unsafe_xml if xml.match?(/<!ENTITY|<!DOCTYPE/i)

    document = Nokogiri::XML(xml) { |config| config.nonet.strict }
    document.remove_namespaces!
    document.xpath("//p").map { |paragraph| docx_paragraph(paragraph) }.reject(&:empty?).join("\n\n").presence || raise(Refused, :unreadable)
  rescue Zip::Error, Nokogiri::XML::SyntaxError
    raise Refused, :unreadable
  end

  def self.docx_paragraph(paragraph)
    text = paragraph.xpath(".//t").map(&:text).join.strip
    level = paragraph.at_xpath("pPr/pStyle/@val")&.value.to_s[/\AHeading(\d)\z/, 1]
    level && text.present? ? "#{'#' * level.to_i} #{text}" : text
  end
  private_class_method :docx_paragraph

  def self.text(bytes)
    string = bytes.dup.force_encoding("UTF-8")
    raise Refused, :unsupported_type unless string.valid_encoding? && !string.include?("\u0000")

    string.match?(/\A\s*(<!doctype html|<html)/i) ? html(string) : string.delete("﻿")
  end

  def self.html(string)
    page = Nokogiri::HTML(string)
    page.css("script, style, noscript, template").remove
    page.css("h1, h2, h3, h4, h5, h6, p, li, tr, pre").map do |node|
      text = node.name == "tr" ? node.css("th, td").map { |cell| cell.text.squish }.join(" | ") : node.text.squish
      node.name.match?(/\Ah[1-6]\z/) ? "#{'#' * node.name[1].to_i} #{text}" : text
    end.reject(&:empty?).join("\n\n").presence || raise(Refused, :unreadable)
  end
  private_class_method :html
end
