# A company of a group: how it is consolidated (full: global integration; equity: the simple equity method), in what currency it keeps its accounts,
# when it entered and left the scope, and the percentage held, with the history of its changes by date of effect.
class Consolidation::Member < ApplicationRecord
  METHODS = %w[full equity].freeze

  belongs_to :group, class_name: "Consolidation::Group", foreign_key: :consolidation_group_id, inverse_of: :members
  belongs_to :member_entity, class_name: "Entity"
  has_many :stakes, -> { order(:effective_on) }, class_name: "Consolidation::Stake", foreign_key: :consolidation_member_id, inverse_of: :member, dependent: :destroy

  validates :method, inclusion: { in: METHODS }
  validates :currency, inclusion: { in: Accounting::MoneyPresenter::SUPPORTED_CURRENCIES }
  validates :member_entity_id, uniqueness: { scope: :consolidation_group_id }
  validate :left_after_joined

  def full? = method == "full"
  def equity? = method == "equity"
  def parent? = member_entity_id == group.entity_id

  # The percentage held at a date: the last one whose date of effect has come; nil when none.
  def stake_on(date) = stakes.select { |stake| stake.effective_on <= date }.last&.percentage

  # In the scope at the reporting date?
  def in_scope_on?(date) = (joined_on.nil? || joined_on <= date) && (left_on.nil? || left_on > date)

  # Joined or left during the period that ends at `date` (from `from`): a change of scope that needs a rule nobody has validated.
  def scope_changed_between?(from, date) = (joined_on && joined_on > from && joined_on <= date) || (left_on && left_on > from && left_on <= date)

  private

  def left_after_joined
    errors.add(:left_on, "must be after the date of entry") if joined_on && left_on && left_on <= joined_on
  end
end
