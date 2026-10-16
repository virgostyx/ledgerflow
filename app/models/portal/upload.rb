# B02b: a file sent by a person of the portal, received in numbered chunks so that a cut network costs only the chunk in flight. Nothing in it is trusted: it stays in quarantine
# (status `received`) until the firm's side has checked it. Only the server's clock counts.
class Portal::Upload < ApplicationRecord
  CHUNK_SIZE = 1.megabyte
  MAX_BYTES = 25.megabytes
  VALIDITY = 48.hours
  HINT_KINDS = %w[purchase sale expense_report statement other].freeze
  NOTE_LIMIT = 300

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :portal_user
  has_many :chunks, -> { order(:position) }, class_name: "Portal::UploadChunk", foreign_key: :upload_id, inverse_of: :upload

  has_secure_token :token
  enum :status, { receiving: "receiving", received: "received" }, default: "receiving"

  validates :filename, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_BYTES }
  validates :sha256, format: { with: /\A\h{64}\z/ }
  validates :hint_kind, inclusion: { in: HINT_KINDS }
  validates :hint_note, length: { maximum: NOTE_LIMIT }

  before_validation { self.sha256 = sha256.to_s.downcase }

  # The companies where a right in force lists documents.upload and the feature is on.
  def self.companies_open_to(person)
    Portal::Company.where(upload_enabled: true, id: person.open_grants.where("portal_grants.capabilities @> ?", [ "documents.upload" ].to_json).select(:entity_id))
  end

  # The uploads of this person, in the companies where they may still send.
  def self.of(person) = where(portal_user_id: person.id, entity_id: companies_open_to(person).select(:id))

  def to_param = token

  def expired? = expires_at <= Time.current

  def received_positions = chunks.pluck(:position)

  def expected_size(position) = position == chunk_count - 1 ? byte_size - (chunk_count - 1) * chunk_size : chunk_size

  # A chunk replayed with the same content changes nothing; another content for the same place is a conflict.
  def store_chunk!(position, bytes, checksum)
    raise Portal::UploadRefused.new("closed", status: :conflict) unless receiving?
    raise Portal::UploadRefused.new("expired", status: :gone) if expired?
    raise Portal::UploadRefused.new("no such chunk", status: :unprocessable_content) unless position.between?(0, chunk_count - 1)
    raise Portal::UploadRefused.new("wrong size", status: :unprocessable_content) unless bytes.bytesize == expected_size(position)

    digest = Digest::SHA256.hexdigest(bytes)
    raise Portal::UploadRefused.new("checksum mismatch", status: :unprocessable_content) unless digest == checksum.to_s.downcase

    existing = chunks.find_by(position: position)
    return check_same!(existing, digest) if existing

    chunks.create!(position: position, byte_size: bytes.bytesize, sha256: digest, content: bytes)
  rescue ActiveRecord::RecordNotUnique
    check_same!(chunks.find_by!(position: position), digest)
  end

  # Every chunk there and the whole is the file announced: the upload is received. Asked again, it answers the same.
  def complete!
    return self if received?
    raise Portal::UploadRefused.new("expired", status: :gone) if expired?

    missing = (0...chunk_count).to_a - received_positions
    raise Portal::UploadRefused.new("chunks missing", status: :unprocessable_content, missing: missing) if missing.any?
    raise Portal::UploadRefused.new("the whole is not the file announced", status: :unprocessable_content) unless Digest::SHA256.hexdigest(bytes) == sha256

    update!(status: "received", received_at: Time.current)
    self
  end

  def bytes = chunks.reload.map(&:content).join.b

  private

  def check_same!(existing, digest)
    raise Portal::UploadRefused.new("another content for this chunk", status: :conflict) unless existing.sha256 == digest

    existing
  end
end
