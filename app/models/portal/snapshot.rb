# B02c: the figures the firm's side prepared for the client's dashboard, from the books, as they were at `known_at`. Only the indicators of the whitelist, no name of a third party. The client
# reads the latest published one; he never triggers a calculation. Amounts are strings with two decimals.
class Portal::Snapshot < ApplicationRecord
  INDICATORS = %w[cash sales_month sales_previous_month sales_last_year result_ytd receivables_overdue receivables_overdue_count payables_30_days].freeze
  SERIES = %w[sales cash].freeze

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false

  scope :published, -> { where(status: "published") }

  # The snapshot a client sees of a company: the latest one the firm let through.
  def self.latest_for(entity_id) = published.where(entity_id: entity_id).order(generated_at: :desc, id: :desc).first

  def self.shown_word(snapshot) = (snapshot.accountant_word if snapshot.word_approved_at.present?)
end
