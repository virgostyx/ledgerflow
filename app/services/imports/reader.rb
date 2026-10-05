require "csv"

# F13a: a CSV or XLSX file read into plain strings, whatever its encoding or separator. Dates of an XLSX come out as ISO (the cell holds a
# date, there is nothing to guess); everything else is text, read again by the kind of import (dates, amounts) with the options of the user.
class Imports::Reader
  Table = Struct.new(:headers, :rows, :lines, keyword_init: true)
  class Unreadable < StandardError; end

  MAX_ROWS = Integer(ENV.fetch("IMPORT_MAX_ROWS", 50_000))
  SEPARATORS = [ ";", ",", "\t", "|" ].freeze
  NS = { "m" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main" }.freeze

  def self.read(data, filename:)
    raise Unreadable, "The file is empty" if data.blank?

    grid = File.extname(filename.to_s).casecmp?(".xlsx") ? xlsx_grid(data) : csv_grid(data)
    # [line number, cells] of every row that holds something
    rows = grid.each_with_index.filter_map { |cells, i| [ i + 1, cells.map { |c| c.to_s.strip } ] if cells.any?(&:present?) }
    raise Unreadable, "The file is empty" if rows.empty?
    raise Unreadable, "The file has more than #{MAX_ROWS} rows" if rows.size - 1 > MAX_ROWS

    Table.new(headers: rows.first.last, rows: rows.drop(1).map(&:last), lines: rows.drop(1).map(&:first))
  end

  def self.csv_grid(data)
    text = data.dup.force_encoding(Encoding::UTF_8)
    text = data.dup.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8) unless text.valid_encoding?
    text = text.delete_prefix("﻿")
    CSV.parse(text, col_sep: SEPARATORS.max_by { |s| text.lines.first.to_s.count(s) }, liberal_parsing: true)
  rescue CSV::MalformedCSVError, Encoding::UndefinedConversionError => e
    raise Unreadable, "The file cannot be read as CSV (#{e.message})"
  end

  # The first sheet. Shared strings, inline strings and numbers; a number whose style is a date format becomes an ISO date.
  def self.xlsx_grid(data)
    Zip::File.open_buffer(StringIO.new(data)) do |zip|
      read_entry = ->(name) { (e = zip.find_entry(name)) && Nokogiri::XML(e.get_input_stream.read).remove_namespaces! }
      strings = read_entry.("xl/sharedStrings.xml")&.xpath("//si")&.map { |si| si.xpath(".//t").map(&:text).join } || []
      dates   = date_styles(read_entry.("xl/styles.xml"))
      sheet   = read_entry.("xl/worksheets/sheet1.xml") or raise Unreadable, "The workbook has no first sheet"
      return sheet.xpath("//sheetData/row").map { |row| row_cells(row, strings, dates) }
    end
  rescue Zip::Error, Nokogiri::SyntaxError
    raise Unreadable, "The file cannot be read as XLSX"
  end

  def self.row_cells(row, strings, dates)
    row.xpath("c").each_with_object([]) do |cell, cells|
      column = cell["r"].to_s[/\A[A-Z]+/].to_s.each_char.reduce(0) { |n, ch| n * 26 + ch.ord - 64 } - 1
      value  = cell.at_xpath("v")&.text
      cells[column] = case cell["t"]
      when "s"         then strings[value.to_i]
      when "inlineStr" then cell.xpath(".//t").map(&:text).join
      when "b"         then value == "1" ? "true" : "false"
      else
        value && dates.include?(cell["s"].to_i) ? (Date.new(1899, 12, 30) + value.to_f.floor).iso8601 : value
      end
    end.map(&:to_s)
  end

  # The indexes (cellXfs) of the styles that show a date.
  def self.date_styles(styles)
    return [] unless styles

    custom = styles.xpath("//numFmts/numFmt").to_h { |f| [ f["numFmtId"].to_i, f["formatCode"].to_s ] }
    styles.xpath("//cellXfs/xf").each_with_index.filter_map do |xf, i|
      id = xf["numFmtId"].to_i
      i if (14..22).cover?(id) || (45..47).cover?(id) || custom[id].to_s.delete("\"").match?(/[dmy]/i) && !custom[id].to_s.match?(/General|0\.0|#/i)
    end
  end
  private_class_method :csv_grid, :xlsx_grid, :row_cells, :date_styles
end
