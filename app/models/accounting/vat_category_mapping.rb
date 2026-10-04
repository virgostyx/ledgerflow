# What a UBL VAT category means for the entity (F06): its VAT treatment on a purchase (Accounting::Invoice#vat_treatment) and, for a treatment
# where the buyer self-assesses the VAT, the rate to apply. Editable data. S, Z, E and O are ready by default (an ordinary purchase); AE, K and G
# are tax decisions (reverse charge, intra-community, export): they stay unmapped, and a document that carries one waits for the accountant.
class Accounting::VatCategoryMapping < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_vat_category_mappings"

  CATEGORIES = %w[S Z E AE K G O].freeze
  DEFAULTS = %w[S Z E O].freeze

  acts_as_tenant :entity

  enum :vat_treatment, Accounting::Invoice.vat_treatments.symbolize_keys.transform_values(&:itself)

  validates :category, inclusion: { in: CATEGORIES }, uniqueness: { scope: :entity_id }
  validates :vat_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Idempotent: what the entity already chose is left as it is.
  def self.ensure_defaults!
    DEFAULTS.each { |category| find_or_create_by!(category: category) { |m| m.vat_treatment = :domestic } }
  end
end
