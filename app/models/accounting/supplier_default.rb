# What was last used for a supplier (F06): the expense account, the journal, the VAT treatment and the payment terms. Feeds the proposals for the
# next invoice received from that supplier. Written when a supplier invoice is posted (Accounting::RememberSupplierDefaults).
class Accounting::SupplierDefault < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_supplier_defaults"

  acts_as_tenant :entity

  enum :vat_treatment, Accounting::Invoice.vat_treatments.symbolize_keys.transform_values(&:itself)

  belongs_to :partner, class_name: "Accounting::Partner"
  belongs_to :account, class_name: "Accounting::Account", optional: true
  belongs_to :journal, class_name: "Accounting::Journal", optional: true

  validates :partner_id, uniqueness: true
end
