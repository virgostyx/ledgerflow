# F13a: what a file would do, worked out without writing anything. `items` are what would be written, `errors` what is refused
# ({ ref:, lines:, message: } where ref names the piece or the row), `skipped` what is already there, `unknowns` the values of the
# file that name nothing yet (to link or, for partners, to create on confirmation).
Imports::Analysis = Struct.new(:read, :items, :errors, :skipped, :warnings, :unknowns, keyword_init: true) do
  def self.blank = new(read: 0, items: [], errors: [], skipped: [], warnings: [], unknowns: Hash.new { |h, k| h[k] = [] })

  def refuse(ref, lines, message) = errors << { ref: ref, lines: Array(lines), message: message }
  def unknown(kind, value) = (unknowns[kind] << value unless unknowns[kind].include?(value))
end
