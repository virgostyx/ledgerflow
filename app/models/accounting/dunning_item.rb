# One customer in a run (F09): the level, the open lines it covers with what was owed on each when it was prepared, the text, and what became of it.
class Accounting::DunningItem < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "dunning_items"

  acts_as_tenant :entity

  enum :channel, { email: 0, letter: 1 }
  enum :status,  { pending: 0, sent: 1, bounced: 2, opened: 3, queued: 4 } # queued: validated, waiting for its delivery

  belongs_to :run, class_name: "Accounting::DunningRun", foreign_key: :dunning_run_id, inverse_of: :items
  belongs_to :partner, class_name: "Accounting::Partner"
  has_one_attached :letter_pdf # the letter as printed, kept for a letter (an e-mail keeps its message id)
  has_many :item_lines, class_name: "Accounting::DunningItemLine", foreign_key: :dunning_item_id, inverse_of: :item, dependent: :destroy

  validates :level, :proposed_level, inclusion: { in: Accounting::DunningPolicy::LEVELS }
  validates :recipient, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { email? && !excluded? }

  validate :one_campaign_a_day, unless: :excluded?

  # A level higher than the one proposed needs an explicit confirmation before anything goes out.
  def skips_level? = level > proposed_level

  def grand_total = total + fees + interest + indemnity

  # The other item of the same customer on the same day, if any (an item left out of its run does not count).
  def same_day_item = self.class.where(partner_id: partner_id, run_on: run_on, excluded: false).where.not(id: id).first

  private

  def one_campaign_a_day
    errors.add(:base, "#{partner.name} is already in a campaign of #{run_on}") if same_day_item
  end
end
