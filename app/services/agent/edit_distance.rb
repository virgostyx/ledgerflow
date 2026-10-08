# How far a person's text is from the one the assistant proposed (A11): the number of single-character changes (Levenshtein), to measure what is used as it is and what is rewritten. Texts are a few thousand
# characters at most, so the plain two-row version is enough.
module Agent::EditDistance
  def self.between(a, b)
    a, b = a.to_s, b.to_s
    return b.length if a.empty?
    return a.length if b.empty?

    previous = (0..b.length).to_a
    a.each_char.with_index(1) do |char, i|
      current = [ i ]
      b.each_char.with_index(1) { |other, j| current << [ current[j - 1] + 1, previous[j] + 1, previous[j - 1] + (char == other ? 0 : 1) ].min }
      previous = current
    end
    previous.last
  end
end
