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
  enum :status, { receiving: "receiving", received: "received", accepted: "accepted", refused: "refused", to_complete: "to_complete" }, default: "receiving"

  validates :filename, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_BYTES }
  validates :sha256, format: { with: /\A\h{64}\z/ }
  validates :hint_kind, inclusion: { in: HINT_KINDS }
  validates :hint_note, length: { maximum: NOTE_LIMIT }
  validates :page_count, numericality: { only_integer: true, in: 1..Rails.configuration.x.portal_uploads[:files_per_action] }, if: :batch_token
  validates :page_number, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: :page_count }, if: -> { batch_token && page_count }

  # What the client is told about a send. Nothing of the books: where it stands, in words of their own.
  CLIENT_STATUSES = { "received" => "Received", "in_progress" => "In progress", "booked" => "Booked", "to_complete" => "To complete", "refused" => "Refused" }.freeze
  REFUSALS = {
    "duplicate" => "This file was already sent.", "corrupted" => "The file cannot be read. Please send it again.", "unsupported_type" => "This kind of file is not accepted.",
    "too_many_pages" => "The document has more than 100 pages.", "image_too_large" => "The image is too large.", "infected" => "The file was not accepted for security reasons.",
    "too_large" => "The file is too large.", "empty" => "The file is empty.", "illegible" => "The document is illegible. Please send a clearer copy.",
    "out_of_scope" => "This document is not needed for the accounts."
  }.freeze

  before_validation { self.sha256 = sha256.to_s.downcase }

  # The companies where a right in force lists documents.upload and the feature is on.
  def self.companies_open_to(person)
    Portal::Company.where(upload_enabled: true, id: person.open_grants.where("portal_grants.capabilities @> ?", [ "documents.upload" ].to_json).select(:entity_id))
  end

  # The uploads of this person, in the companies where they may still send.
  belongs_to :request_line, class_name: "Portal::DocumentRequestLine", optional: true

  def self.of(person) = where(portal_user_id: person.id, entity_id: companies_open_to(person).select(:id))

  def to_param = token

  # => the quota the person has reached, as a sentence, or nil
  def self.quota_message(person, entity_id, size)
    limits = Rails.configuration.x.portal_uploads
    if where(portal_user_id: person.id).where(created_at: 24.hours.ago..).count >= limits[:files_per_day]
      "You reached the daily limit of #{limits[:files_per_day]} files. Please try again tomorrow."
    elsif where(entity_id: entity_id).where(created_at: Time.current.beginning_of_month..).sum(:byte_size) + size > limits[:bytes_per_month]
      "The monthly volume of your company is reached. Please contact your accountant."
    end
  end

  def client_status
    return "refused" if refused?
    return "to_complete" if to_complete?

    accepted? ? progress : "received"
  end

  def client_status_label = CLIENT_STATUSES.fetch(client_status)

  def refusal_message = REFUSALS.fetch(refusal_reason.to_s, "The file was not accepted.")

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

  # Once the file is taken in or refused, nothing of it stays in quarantine. Only the firm's side does this: the portal's database role cannot delete.
  def purge_chunks! = Portal::UploadChunk.where(upload_id: id).delete_all

  def bytes = chunks.reload.map(&:content).join.b

  private

  def check_same!(existing, digest)
    raise Portal::UploadRefused.new("another content for this chunk", status: :conflict) unless existing.sha256 == digest

    existing
  end
end
