# B03c: the public part of a key that signs certificates (table `certificate_signing_keys`). Not of a company: of the instance. Never deleted: a certificate has to be
# verifiable as long as it exists. The private part is a file outside the application (see Ledger::SigningKeys).
class Ledger::SigningKey < ApplicationRecord
  self.table_name = "certificate_signing_keys"

  STATUSES = %w[active retired revoked].freeze

  validates :key_id, :public_key, :fingerprint, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :chronological, -> { order(:created_at, :id) }

  before_destroy { throw :abort }
end
