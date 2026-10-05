# One consolidation of a group at a reporting date: a draft while it is worked on (what was collected is kept in `figures`), validated by the owner,
# then FROZEN: its content and SHA-256 are written once, and it never changes again (a new consolidation is a new run, which shows its differences
# with the previous one).
class Consolidation::Run < ApplicationRecord
  STATUSES = %w[draft validated frozen].freeze

  acts_as_tenant :entity

  belongs_to :group, class_name: "Consolidation::Group", foreign_key: :consolidation_group_id, inverse_of: :runs
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  belongs_to :frozen_by, class_name: "User", optional: true
  belongs_to :previous_run, class_name: "Consolidation::Run", optional: true
  has_many :entries, class_name: "Consolidation::Entry", foreign_key: :consolidation_run_id, inverse_of: :run, dependent: :destroy

  validates :reporting_date, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_update :refuse_change_when_frozen
  before_destroy { throw :abort if frozen? }

  def draft? = status == "draft"
  def validated? = status == "validated"
  def frozen? = status == "frozen"

  # The frozen content has not been touched since it was frozen.
  def intact? = frozen? && snapshot_sha256 == Accounting::ClosingSnapshot.fingerprint(snapshot)

  def self.fingerprint(content) = Accounting::ClosingSnapshot.fingerprint(content)

  private

  def refuse_change_when_frozen
    errors.add(:base, "a frozen run never changes") if status_was == "frozen"
    throw :abort if errors.any?
  end
end
