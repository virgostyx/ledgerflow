# B03c: a signed certificate of the integrity of the books (table `integrity_certificates`). `body` is what was signed, byte for byte (canonical JSON, RFC 8785); `signature` is
# the Ed25519 signature of `key_id` over it. Never changed; revoked, with a reason, only for an error of issue.
class IntegrityCertificate < ApplicationRecord
  DISCLOSURES = %w[minimal standard full].freeze

  acts_as_tenant :entity

  belongs_to :issued_by, class_name: "User"
  belongs_to :revoked_by, class_name: "User", optional: true
  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear", optional: true

  validates :disclosure_level, inclusion: { in: DISCLOSURES }
  validates :uuid, :body, :signature, :key_id, presence: true

  before_destroy { throw :abort }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def revoked? = revoked_at.present?

  def to_param = uuid

  def payload_hash = JSON.parse(body)

  # The certificate as a file: what was signed, and the signature with the key that made it.
  def to_document = payload_hash.merge("signature" => { "key_id" => key_id, "algorithm" => "Ed25519", "value" => signature })
end
