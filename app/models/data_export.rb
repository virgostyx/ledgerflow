# F13b: a full backup of an entity: who asked, its state, and the ZIP while it is kept. A new link is signed each time the page is shown.
class DataExport < ApplicationRecord
  STATUSES = %w[processing ready failed expired].freeze
  KEEP_FOR = 7.days
  LINK_FOR = 1.hour

  acts_as_tenant :entity

  belongs_to :user, optional: true
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }

  scope :stale, -> { where(status: "ready").where("expires_at < ?", Time.current) }

  def ready? = status == "ready"
  def link_token = signed_id(purpose: :data_export, expires_in: LINK_FOR)
end
