# The text of a SEPA payment file (B01b): the names and the remittances may only carry the SEPA basic character set (letters and digits, and / - ? : ( ) . , ' + and the space).
# Anything else is turned into its letter (an accent, a ligature) or, when it has none, into a space - the same way every time, so that a file is the same every time.
# `changes` says what would be changed, for the pre-flight report: a person sees it before the file goes out.
module Payments::SepaText
  ALLOWED = %r{[A-Za-z0-9/\-?:().,'+ ]}
  EXTRA = { "ß" => "ss", "Æ" => "AE", "æ" => "ae", "Ø" => "O", "ø" => "o", "Œ" => "OE", "œ" => "oe", "Đ" => "D", "đ" => "d", "Ł" => "L", "ł" => "l", "Þ" => "Th", "þ" => "th", "ð" => "d" }.freeze

  def self.clean(text, max: nil)
    cleaned = text.to_s.each_char.map { |char| transliterate(char) }.join
    max ? cleaned[0, max] : cleaned
  end

  # => { original => cleaned } when the text would change, else nil.
  def self.changes(text)
    cleaned = clean(text)
    { text.to_s => cleaned } if cleaned != text.to_s
  end

  def self.transliterate(char)
    return char if char.match?(ALLOWED)

    mapped = EXTRA[char] || I18n.transliterate(char, replacement: " ")
    mapped.each_char.map { |c| c.match?(ALLOWED) ? c : " " }.join
  end
  private_class_method :transliterate
end
