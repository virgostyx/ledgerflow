# The contrast ratio of two colours, as WCAG 2 defines it (relative luminance of sRGB). AA asks 4.5 to 1 for normal text.
module Portal::Contrast
  AA = 4.5

  def self.ratio(first, second)
    light, dark = [ luminance(first), luminance(second) ].sort.reverse
    (light + 0.05) / (dark + 0.05)
  end

  def self.luminance(hex)
    red, green, blue = hex.delete("#").scan(/../).map { |pair| channel(pair.to_i(16) / 255.0) }
    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  def self.channel(value) = value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
  private_class_method :luminance, :channel
end
