module Accounting::MonetaryPrecision
  extend ActiveSupport::Concern

  MONETARY_COLUMNS = %w[debit credit amount vat_amount amount_currency
                        balance_debit balance_credit opening_balance
                        unit_price subtotal_excl_vat total_incl_vat
                        vat_rate quantity].freeze

  included do
    before_validation :coerce_monetary_fields_to_bigdecimal
  end

  private

  def coerce_monetary_fields_to_bigdecimal
    MONETARY_COLUMNS.each do |col|
      next unless respond_to?(col) && !send(col).nil?
      value = send(col)
      send(:"#{col}=", BigDecimal(value.to_s)) unless value.is_a?(BigDecimal)
    end
  end
end
