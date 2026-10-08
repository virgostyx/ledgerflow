# The agent's settings for one entity (A01, A04): off until an owner turns it on and accepts the data processing terms; how long conversations are kept; and, class of data by class
# of data, what goes to the language model: as it is (send), masked (mask) or never (block). The restricted mode lets only aggregates go: no free text, no name of a person or a
# company, no identifier. Only an owner changes them, and every change is in the audit trail.
class Agent::Setting < ApplicationRecord
  include Accounting::AuditTrailed

  self.table_name = "agent_settings"

  RETENTION_CHOICES = [ 30, 90, 365 ].freeze
  DATA_CLASSES = Agent::Tools::Base::FIELD_CLASSES.map(&:to_s).freeze
  MODES = %w[send mask block].freeze
  # The prudent defaults of the spec (§7): the figures and the technical identifiers go, the people are masked, the free text goes after cleaning.
  DEFAULT_MODES = { "public_ref" => "send", "financial" => "send", "personal" => "mask", "bank_identifier" => "mask", "tax_identifier" => "mask", "free_text" => "send" }.freeze
  RESTRICTED_BLOCKS = %w[personal bank_identifier tax_identifier free_text].freeze

  acts_as_tenant :entity

  # What may leave of a document (A09): the masked text only. `full_document` (the file itself, unmasked) is not offered: it needs the explicit agreement of the product and of the owner first.
  DOCUMENT_MODES = %w[text_only].freeze

  validates :retention_days, inclusion: { in: RETENTION_CHOICES }
  validates :document_mode, inclusion: { in: DOCUMENT_MODES }
  validates :review_threshold, numericality: { greater_than_or_equal_to: 0, less_than: 10**13 }
  validate :modes_are_known

  def self.for_current_entity = find_or_create_by!(entity: ActsAsTenant.current_tenant)

  # What is done with a class of data: the restricted mode blocks what is not an aggregate, whatever the owner chose.
  def mode_for(data_class)
    data_class = data_class.to_s
    return "block" if restricted? && RESTRICTED_BLOCKS.include?(data_class)

    data_class_modes.fetch(data_class) { DEFAULT_MODES.fetch(data_class) }
  end

  def modes = DATA_CLASSES.index_with { |data_class| mode_for(data_class) }

  private

  def modes_are_known
    unknown = data_class_modes.keys - DATA_CLASSES
    errors.add(:data_class_modes, "unknown class: #{unknown.join(', ')}") if unknown.any?
    bad = data_class_modes.values - MODES
    errors.add(:data_class_modes, "unknown mode: #{bad.join(', ')}") if bad.any?
  end
end
