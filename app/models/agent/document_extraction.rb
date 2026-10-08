# What the model read from a document (A09), kept as a proposal until a person confirms it field by field, or all at once when nothing is weak. The content is encrypted: it holds the business data of the
# document. Nothing here is the document's data: the confirmed fields are written into it through the same door as the ones a person confirms from F03 (Accounting::ConfirmDocumentField).
class Agent::DocumentExtraction < ApplicationRecord
  self.table_name = "agent_document_extractions"

  acts_as_tenant :entity

  belongs_to :document, class_name: "Accounting::Document"
  belongs_to :requested_by, class_name: "User"
  belongs_to :confirmed_by, class_name: "User", optional: true

  encrypts :payload

  enum :status, { proposed: "proposed", confirmed: "confirmed", rejected: "rejected", failed: "failed" }, default: "proposed"

  scope :to_confirm, -> { proposed.order(:id) }

  def data = @data ||= payload.present? ? JSON.parse(payload) : {}
  def fields = data.fetch("fields", {})
  def warnings = data.fetch("warnings", [])
  def entry_allowed? = %w[invoice credit_note].include?(document_type)

  # A field that needs a person's word before it can be confirmed with the others: weak, invalid, or not found.
  def weak_fields = fields.select { |_, field| %w[needs_confirmation not_found].include?(field["state"]) }.keys

  # "Confirm all" is possible only when nothing is weak and something was read.
  def confirm_all? = proposed? && fields.any? { |_, field| field["value"] } && weak_fields.empty?

  def update_field!(name, attributes)
    fields[name] = fields.fetch(name).merge(attributes)
    update!(payload: data.merge("fields" => fields).to_json)
    @data = nil
  end
end
