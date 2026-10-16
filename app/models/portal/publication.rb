# What the firm shows to the people of the portal: frozen at publication (the database refuses any change but the marks of replacement and withdrawal).
class Portal::Publication < ApplicationRecord
  KINDS = %w[monthly_report situation vat_summary document_request other].freeze

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :published_by, class_name: "User"
  belongs_to :replaces, class_name: "Portal::Publication", optional: true
  belongs_to :replaced_by, class_name: "Portal::Publication", optional: true
  belongs_to :withdrawn_by, class_name: "User", optional: true
  has_many :files, -> { order(:position) }, class_name: "Portal::PublicationFile", foreign_key: :publication_id, inverse_of: :publication
  has_many :recipient_rows, class_name: "Portal::PublicationRecipient", foreign_key: :publication_id, inverse_of: :publication
  has_many :recipients, through: :recipient_rows, source: :portal_user
  has_many :approver_rows, class_name: "Portal::PublicationApprover", foreign_key: :publication_id, inverse_of: :publication
  has_many :approvers, through: :approver_rows, source: :portal_user
  has_many :approvals, class_name: "Portal::Approval", foreign_key: :publication_id, inverse_of: :publication

  enum :status, { published: "published", withdrawn: "withdrawn" }, default: "published"

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true

  # What a client can be shown: published, not replaced by a newer version, not out of date.
  scope :visible, -> { published.where(replaced_by_id: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # What a person may reach: the companies where a right in force lists publications.view, and the publications addressed to everyone or to them. Withdrawn and old
  # ones included (see `visible` for what is shown).
  scope :in_reach_of, lambda { |person|
    entity_ids = person.open_grants.where("portal_grants.capabilities @> ?", [ "publications.view" ].to_json).select(:entity_id)
    where(entity_id: entity_ids).where(<<~SQL.squish, person.id)
      NOT EXISTS (SELECT 1 FROM portal_publication_recipients r WHERE r.publication_id = portal_publications.id)
      OR EXISTS (SELECT 1 FROM portal_publication_recipients r WHERE r.publication_id = portal_publications.id AND r.portal_user_id = ?)
    SQL
  }

  def approver?(person) = requires_approval? && approver_rows.exists?(portal_user_id: person.id)

  def to_param = token
end
