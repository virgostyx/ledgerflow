# F12a: what an entity said of its own health on a day. Written by Portfolio::Snapshot from the books of that entity alone; read by the dashboard, which
# therefore never reads the books of several entities. One per entity and day.
class DossierHealthSnapshot < ApplicationRecord
  belongs_to :entity

  validates :taken_on, :computed_at, presence: true
  validates :taken_on, uniqueness: { scope: :entity_id }

  # The most recent snapshot of each of these entities.
  scope :latest_of, ->(entity_ids) { where(id: where(entity_id: entity_ids).select("DISTINCT ON (entity_id) id").order(:entity_id, taken_on: :desc)) }

  def never_checked? = blocking_count.nil?
end
