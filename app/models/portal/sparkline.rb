# B02c: the little curve of a series, as an SVG path computed on the page itself (no script, no library, nothing from outside). The values are read as decimals; only the coordinates drawn
# are rounded. The same numbers are always given in a table next to it.
module Portal::Sparkline
  WIDTH = 120
  HEIGHT = 32

  # => the "points" of a polyline for the values (strings with decimals), or nil when there is nothing to draw
  def self.points(values)
    numbers = values.map { |v| BigDecimal(v.to_s) }
    return if numbers.size < 2

    low, high = numbers.minmax
    span = high - low
    step = BigDecimal(WIDTH) / (numbers.size - 1)
    numbers.each_with_index.map do |n, i|
      y = span.zero? ? BigDecimal(HEIGHT) / 2 : BigDecimal(HEIGHT) - (n - low) / span * HEIGHT
      "#{(step * i).round(1).to_s('F')},#{y.round(1).to_s('F')}"
    end.join(" ")
  end
end
