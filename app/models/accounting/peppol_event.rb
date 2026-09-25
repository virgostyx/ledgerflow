# One step in the Peppol life of an invoice: handed to the Access Point (sent), then delivered or failed.
class Accounting::PeppolEvent < ApplicationRecord
  self.table_name = "accounting_peppol_events"

  acts_as_tenant :entity

  enum :kind, { sent: 0, delivered: 1, failed: 2 }

  belongs_to :invoice, class_name: "Accounting::Invoice"

  before_validation { self.occurred_at ||= Time.current }
end
