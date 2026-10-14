# B03b: a change of the report of changes marked as reviewed (`change_key` says which one, see Changes::Key). One per change, visible to the whole company, never edited.
class Accounting::ChangeReview < ApplicationRecord
  self.table_name = "accounting_change_reviews"

  acts_as_tenant :entity

  belongs_to :reviewer, class_name: "User"

  validates :change_key, :reviewed_at, presence: true
  validates :change_key, uniqueness: { scope: :entity_id }
end
