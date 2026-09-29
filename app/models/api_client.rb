class ApiClient < ApplicationRecord
  SCOPES = %w[invoices:read invoices:write partners:write].freeze

  # Not acts_as_tenant: the client designates the tenant, it is looked up before any tenant is set.
  belongs_to :entity

  has_many :api_requests, dependent: :destroy

  validates :name, presence: true
  validates :key_digest, presence: true, uniqueness: true
  validate  :known_scopes

  # Returns [client, plaintext_key]; the key can't be recovered afterwards.
  def self.issue!(**attrs)
    key    = generate_key
    client = create!(attrs.merge(key_digest: digest(key)))
    [ client, key ]
  end

  def self.authenticate(key)
    return if key.blank?

    find_by(key_digest: digest(key), active: true)
  end

  def self.generate_key = "lf_#{SecureRandom.urlsafe_base64(32)}"
  def self.digest(key) = Digest::SHA256.hexdigest(key)

  def allows?(scope) = scopes.include?(scope)

  def revoke! = update!(active: false)

  def rotate!
    key = self.class.generate_key
    update!(key_digest: self.class.digest(key))
    key
  end

  private

  def known_scopes
    unknown = scopes - SCOPES
    errors.add(:scopes, "unknown: #{unknown.join(', ')}") if unknown.any?
  end
end
