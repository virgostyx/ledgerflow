# One message that went through the Peppol network, in or out (F06). Recorded before anything is done with it, with its XML, so that nothing is
# lost: a message that cannot be worked on is "needs_review" with its reasons, never dropped. Unique per entity, direction and message id.
class Accounting::PeppolMessage < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_peppol_messages"

  acts_as_tenant :entity

  enum :direction,     { inbound: 0, outbound: 1 }
  enum :document_type, { invoice: 0, credit_note: 1, other: 2 }, prefix: :document
  enum :status,        { received: 0, processed: 1, needs_review: 2, queued: 3, delivered: 4, failed: 5, dismissed: 6, retrying: 7 }

  belongs_to :partner,  class_name: "Accounting::Partner", optional: true # the supplier a person picked for a message that could not choose
  belongs_to :invoice,  class_name: "Accounting::Invoice", optional: true
  belongs_to :document, class_name: "Accounting::Document", optional: true

  validates :message_id, presence: true, uniqueness: { scope: %i[entity_id direction] }
  validates :occurred_at, presence: true

  before_validation { self.occurred_at ||= Time.current }

  scope :to_review, -> { needs_review }

  # What the XML says of itself: the kind of document and its process. Tolerant: an unreadable document is "other", and a person looks at it.
  def self.describe(xml)
    doc = Nokogiri::XML(xml.to_s)
    doc.remove_namespaces!
    type = { "Invoice" => "invoice", "CreditNote" => "credit_note" }.fetch(doc.root&.name, "other")
    endpoint = doc.at_xpath("//AccountingSupplierParty//EndpointID")
    sender = ("#{endpoint['schemeID']}:#{endpoint.text.strip}" if endpoint && endpoint["schemeID"].present? && endpoint.text.present?)
    { document_type: type, process: doc.at_xpath("/*/ProfileID")&.text.to_s.strip.presence, sender_id: sender }
  rescue StandardError
    { document_type: "other", process: nil, sender_id: nil }
  end
end
