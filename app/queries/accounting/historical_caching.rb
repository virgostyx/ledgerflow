# B03a: a report read at a past instant is kept (Accounting::KnownAt#cache): what it said then does not change. A report includes this and wraps what `call` computes in
# `cached`, saying what makes its result what it is (`cache_parts`); today's view goes straight through. (Not a prepended `call`: a spec stubs `call` of the report.)
module Accounting::HistoricalCaching
  private

  def cached(&block) = @known_at.cache(self.class.name, cache_parts, &block)
end
