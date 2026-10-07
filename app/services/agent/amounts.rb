# The amounts of a text, as the two-decimal strings the tools give: 1 210,00 and 1,210.00 are 1210.00 (A05). A date, a year, a whole number or an account code is not an amount.
module Agent::Amounts
  MONEY = /(?<![\d.,])\d{1,3}(?:[ .,’]\d{3})*[.,]\d{2}(?![\d])(?![.,]\d)|(?<![\d.,])\d+[.,]\d{2}(?![\d])(?![.,]\d)/

  def self.of(text)
    text.to_s.scan(MONEY).map do |raw|
      digits = raw.gsub(/[ ’]/, "")
      decimal = digits[-3] == "," || digits[-3] == "." ? digits[-3] : nil
      whole = decimal ? digits[0...-3] : digits
      "#{whole.delete('.,')}.#{digits[-2..]}"
    end.uniq
  end

  # Where each amount of the text sits (position and length), so that one can be marked in place.
  def self.spans(text) = text.to_enum(:scan, MONEY).map { Regexp.last_match }.map { |match| [ match.begin(0), match[0].length, of(match[0]).first ] }
end
