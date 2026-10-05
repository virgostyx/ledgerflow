# F13a: what the three imports have in common: the fields a file can fill, the way a cell is read (dates and amounts as the options
# say, never guessed), and the entry points `analyze` (nothing written) and `write` (the objects, tagged with their batch).
class Imports::Kind
  KINDS = %w[partners accounts entries].freeze
  DATE_FORMATS = { "iso" => [ "%Y-%m-%d", "YYYY-MM-DD" ], "dmy" => [ "%d/%m/%Y", "DD/MM/YYYY" ], "mdy" => [ "%m/%d/%Y", "MM/DD/YYYY" ] }.freeze
  NO_BREAK_SPACE = " ".freeze

  # { field => required }, in the order of the mapping screen
  def self.fields = self::FIELDS
  def self.for(kind)
    "Imports::Kinds::#{kind.to_s.camelize}".constantize if KINDS.include?(kind.to_s)
  end

  # The mapping a file proposes by itself: a column whose title is the name of a field.
  def self.propose_mapping(headers)
    fields.keys.each_with_object({}) do |field, mapping|
      header = headers.find { |h| h.to_s.strip.downcase.tr(" -", "__") == field }
      mapping[field] = header if header
    end
  end

  def self.analyze(table, mapping:, options: {}, resolutions: {}) = new(table, mapping, options, resolutions).analyze

  def initialize(table, mapping, options, resolutions)
    @table, @mapping, @options, @resolutions = table, mapping.to_h, options.to_h, resolutions.to_h
    @columns = @table.headers.each_with_index.to_h
  end

  private

  # Is a column mapped to this field, and present in the file?
  def mapped?(field) = @columns.key?(@mapping[field])

  def cell(row, field) = (mapped?(field) ? row[@columns[@mapping[field]]].to_s.strip.presence : nil)

  # => the missing required fields: the mapping is incomplete, nothing can be read
  def unmapped_required = self.class.fields.select { |field, required| required && !mapped?(field) }.keys

  def check_mapping!(analysis)
    missing = unmapped_required
    analysis.refuse(nil, [], "Map a column to: #{missing.join(', ')}") if missing.any?
    missing.none?
  end

  def parse_date(text)
    format, label = DATE_FORMATS.fetch(@options.fetch("date_format", "iso"))
    return Date.strptime(text, format) if text.match?(/\A\d{1,4}[-\/]\d{1,2}[-\/]\d{1,4}\z/)

    raise ArgumentError
  rescue ArgumentError, Date::Error
    raise ArgumentError, "date \"#{text}\" is not #{label}"
  end

  # An amount of at most two decimals; a negative one is refused (the other column is for that).
  def parse_amount(text)
    return BigDecimal("0") if text.blank?

    plain = text.delete(" #{NO_BREAK_SPACE}")
    plain = @options["decimal"] == "," ? plain.delete(".").tr(",", ".") : plain.delete(",")
    raise ArgumentError, "amount \"#{text}\" is not a number" unless plain.match?(/\A-?\d+(\.\d+)?\z/)
    raise ArgumentError, "amount \"#{text}\" is negative: use the other column" if plain.start_with?("-")
    raise ArgumentError, "amount \"#{text}\" has more than 2 decimals" if plain.include?(".") && plain.split(".").last.length > 2

    BigDecimal(plain)
  end
end
