class Entity < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :user_entities, dependent: :destroy
  has_many :users, through: :user_entities

  enum :vat_filing_frequency, { monthly: 0, quarterly: 1 }
  enum :vat_regime,           { normal: 0, franchise: 1 }
  enum :vat_scheme,           { normal: 0, mixed: 1 }, prefix: :vat_scheme
  # The Peppol Access Point of this entity (one adapter per provider, see Peppol::AccessPoint); nil = not set up.
  enum :peppol_access_point,  { simulator: 0, digiteal: 1, b2brouter: 2 }, prefix: :peppol_ap

  serialize :peppol_credentials, type: Hash, coder: JSON
  encrypts  :peppol_credentials
  has_secure_token :peppol_webhook_token
  normalizes :peppol_participant_id, with: ->(id) { id.strip.presence }

  # A blank number must be NULL: the unique index on vat_number only skips NULLs.
  normalizes :vat_number, with: ->(number) { number.strip.presence }

  validates :name,       presence: true
  validates :legal_name, presence: true
  validates :country,    presence: true
  validates :vat_number, uniqueness: true, allow_blank: true
  validate  :vat_number_format
  validates :peppol_participant_id, uniqueness: true, allow_nil: true # routes the documents received to their entity
  validate  :peppol_participant_id_format, :simulator_allowed, :peppol_credentials_complete

  scope :active, -> { where(active: true) }

  private

  def peppol_participant_id_format
    errors.add(:peppol_participant_id, :invalid) unless peppol_participant_id.nil? || Peppol::ParticipantId.valid?(peppol_participant_id)
  end

  # The simulator fakes deliveries: never where the configuration does not allow it (production).
  def simulator_allowed
    return unless peppol_ap_simulator? && !Rails.configuration.x.peppol_simulator_allowed

    errors.add(:peppol_access_point, "the simulator is only available in development and test")
  end

  # What an Access Point needs to be called (API key, secret...) is declared by its adapter.
  def peppol_credentials_complete
    return unless peppol_access_point

    missing = Peppol::AccessPoint.credential_fields(peppol_access_point).select { |f| f[:required] && peppol_credentials[f[:key]].blank? }
    errors.add(:peppol_credentials, "are missing: #{missing.map { |f| f[:label] }.to_sentence}") if missing.any?
  end

  def vat_number_format
    errors.add(:vat_number, :invalid) unless vat_number.blank? || Accounting::Partner.valid_vat_number?(vat_number)
  end
end
