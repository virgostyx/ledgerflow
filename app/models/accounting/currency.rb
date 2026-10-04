# A currency of the ISO 4217 list with its number of decimals (F11): 0 for the yen, 2 for the dollar, 3 for the dinar of Bahrain. Reference data,
# the same for every entity. Amounts in a currency are rounded to its decimals.
class Accounting::Currency < ApplicationRecord
  self.table_name = "currencies"

  validates :code, presence: true, uniqueness: true, format: { with: /\A[A-Z]{3}\z/ }
  validates :decimals, inclusion: { in: [ 0, 2, 3 ] }

  # The number of decimals of a currency; 2 for one that is not on the list (EUR included).
  def self.decimals_of(code)
    @decimals = nil if @decimals && @decimals.size != count # a currency added after the first call
    (@decimals ||= pluck(:code, :decimals).to_h).fetch(code.to_s.upcase, 2)
  end
end
