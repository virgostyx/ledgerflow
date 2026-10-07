# A document of the knowledge base (A06): curated, dated, reviewed by a person. The agent only uses a `reviewed` document that is valid on the date of the question. A document of the platform is
# read-only for every entity, one of an organization for its entities, one of an entity for that entity alone: `visible_to` is the only door to the table.
class Knowledge::Document < ApplicationRecord
  self.table_name = "knowledge_documents"

  SCOPES = %w[platform organization company].freeze
  STATUSES = %w[draft reviewed retired].freeze
  SOURCE_TYPES = %w[pcmn procedure sheet note].freeze
  LANGUAGES = %w[fr nl en].freeze

  belongs_to :entity, optional: true
  belongs_to :organization, optional: true
  belongs_to :author, class_name: "User"
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :chunks, class_name: "Knowledge::Chunk", dependent: :delete_all

  validates :title, :source, :licence, :valid_from, :series, :body, :content_sha256, presence: true
  validates :scope, inclusion: { in: SCOPES }
  validates :status, inclusion: { in: STATUSES }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :language, inclusion: { in: LANGUAGES }
  validates :jurisdiction, format: { with: /\A[A-Z]{2}\z/ }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :series }
  validates :entity, presence: true, if: -> { scope == "company" }
  validates :organization, presence: true, if: -> { scope == "organization" }
  validate :valid_period_is_ordered

  scope :reviewed, -> { where(status: "reviewed") }
  scope :valid_on, ->(date) { where("valid_from <= ?", date).where("valid_to IS NULL OR valid_to >= ?", date) }
  scope :ending_within, ->(days) { reviewed.where(valid_to: Date.current..(Date.current + days)) }

  # What an entity may see: the platform's, its organization's and its own. Nothing of another entity's, ever.
  def self.visible_to(entity)
    where(scope: "platform").or(where(scope: "organization", organization_id: entity.organization_id)).or(where(scope: "company", entity_id: entity.id))
  end

  # What may be quoted to the entity on a day: reviewed, and in force that day.
  def self.usable_by(entity, on: Date.current) = visible_to(entity).reviewed.valid_on(on)

  def series_versions = self.class.where(series: series)
  def editable_by?(entity) = scope == "company" && entity_id == entity.id
  def draft? = status == "draft"
  def reviewed? = status == "reviewed"
  def retired? = status == "retired"
  def ref = Agent::Refs.build("kb", "doc-#{id}")

  # A person other than the author reviews it when four-eyes is on; alone otherwise. Only a draft can be reviewed.
  def review!(user, four_eyes:)
    raise ArgumentError, "only a draft is reviewed" unless draft?
    raise ArgumentError, "four-eyes: the author cannot review their own document" if four_eyes && user.id == author_id

    update!(status: "reviewed", reviewed_by: user, reviewed_at: Time.current)
  end

  # A retired document is not used any more; what quoted it earlier still opens it, marked as retired.
  def retire!
    update!(status: "retired", retired_at: Time.current)
  end

  private

  def valid_period_is_ordered
    errors.add(:valid_to, "must not be before the start of validity") if valid_from && valid_to && valid_to < valid_from
  end
end
