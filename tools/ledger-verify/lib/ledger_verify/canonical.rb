# JSON canonicalisation, RFC 8785 (JCS): the same bytes for the same data, whoever writes them. Standard library only; this file is part of `ledger-verify` and the application
# loads this very file, so that what is written and what is checked cannot drift apart.
#
# Accepted: nil, true, false, Integer within +-(2**53 - 1), Float (finite), String (valid UTF-8), Symbol keys, Array, Hash. A decimal amount travels as a string: BigDecimal,
# dates and times are refused, never guessed at.
module LedgerVerify
  module Canonical
    class Error < StandardError; end

    MAX_SAFE_INTEGER = 2**53 - 1
    ESCAPES = { "\"" => "\\\"", "\\" => "\\\\", "\b" => "\\b", "\t" => "\\t", "\n" => "\\n", "\f" => "\\f", "\r" => "\\r" }.freeze

    def self.generate(value) = write(value).encode(Encoding::UTF_8)

    def self.write(value)
      case value
      when nil then "null"
      when true then "true"
      when false then "false"
      when Integer then integer(value)
      when Float then float(value)
      when String then string(value)
      when Array then "[#{value.map { |item| write(item) }.join(',')}]"
      when Hash then object(value)
      else raise Error, "cannot write #{value.class}: #{value.is_a?(Numeric) ? 'a decimal is written as a string' : 'not a JSON value'}"
      end
    end
    private_class_method :write

    def self.integer(value)
      raise Error, "integer #{value} is beyond what a double holds exactly: write it as a string" if value.abs > MAX_SAFE_INTEGER

      value.to_s
    end
    private_class_method :integer

    # The members sorted by their names as UTF-16 code units (not as bytes, not as code points).
    def self.object(hash)
      members = hash.map { |key, value| [ name(key), value ] }
      duplicate = members.map(&:first).tally.find { |_, count| count > 1 }
      raise Error, "duplicate key #{duplicate.first.inspect}" if duplicate

      "{#{members.sort_by { |key, _| key.encode(Encoding::UTF_16BE).unpack('n*') }.map { |key, item| "#{string(key)}:#{write(item)}" }.join(',')}}"
    end
    private_class_method :object

    def self.name(key)
      raise Error, "a key is a string or a symbol, not #{key.class}" unless key.is_a?(String) || key.is_a?(Symbol)

      key.to_s
    end
    private_class_method :name

    def self.string(text)
      text = text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
      raise Error, "a string must be valid UTF-8" unless text.encoding == Encoding::UTF_8 ? text.valid_encoding? : text.encode(Encoding::UTF_8).valid_encoding?

      body = text.encode(Encoding::UTF_8).each_char.map do |char|
        ESCAPES.fetch(char) { char.ord < 0x20 ? format("\\u%04x", char.ord) : char }
      end.join
      "\"#{body}\""
    rescue EncodingError
      raise Error, "a string must be valid UTF-8"
    end
    private_class_method :string

    # ECMAScript Number::toString: the shortest digits that read back as the same double, laid out by the rules of the language.
    def self.float(number)
      raise Error, "#{number} is not a JSON number" unless number.finite?
      return "0" if number.zero? # -0 too

      digits, point = digits_and_point(number.abs)
      k = digits.length
      body =
        if k <= point && point <= 21 then digits + ("0" * (point - k))
        elsif 0 < point && point <= 21 then "#{digits[0, point]}.#{digits[point..]}"
        elsif -6 < point && point <= 0 then "0.#{'0' * -point}#{digits}"
        else exponent_form(digits, point - 1)
        end
      number.negative? ? "-#{body}" : body
    end
    private_class_method :float

    # value = 0.DIGITS x 10**point, DIGITS without leading or trailing zero.
    def self.digits_and_point(number)
      mantissa, exponent = number.to_s.split("e")
      whole, fraction = mantissa.split(".")
      all = whole + fraction.to_s
      lead = all[/\A0*/].length
      [ all[lead..].sub(/0+\z/, ""), whole.length + exponent.to_i - lead ]
    end
    private_class_method :digits_and_point

    def self.exponent_form(digits, exponent)
      head = digits.length == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
      "#{head}e#{exponent.negative? ? '-' : '+'}#{exponent.abs}"
    end
    private_class_method :exponent_form
  end
end
