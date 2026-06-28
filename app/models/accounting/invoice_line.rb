class Accounting::InvoiceLine < ApplicationRecord
  self.table_name = "accounting_invoice_lines"

  acts_as_tenant :entity

  include Accounting::MonetaryPrecision

  belongs_to :invoice, class_name: "Accounting::Invoice"
  belongs_to :account, class_name: "Accounting::Account"

  validates :description, presence: true
  validates :quantity,    numericality: { greater_than: 0 }
  validates :unit_price,  numericality: { greater_than_or_equal_to: 0 }
  validates :vat_rate,    numericality: { greater_than_or_equal_to: 0 }

  before_validation :compute_amounts

  default_scope { order(:position) }

  def compute_amounts
    return unless quantity && unit_price && vat_rate

    qty   = BigDecimal(quantity.to_s)
    price = BigDecimal(unit_price.to_s)
    rate  = BigDecimal(vat_rate.to_s)

    self.subtotal_excl_vat = (qty * price).round(2)
    self.vat_amount        = (subtotal_excl_vat * rate / 100).round(2)
    self.total_incl_vat    = subtotal_excl_vat + vat_amount
  end
end
