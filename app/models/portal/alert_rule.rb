# B02c: an alert the firm defined for a company: told to the directors when the forecast cash goes under a threshold.
class Portal::AlertRule < ApplicationRecord
  KINDS = %w[cash_below].freeze

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false

  validates :kind, inclusion: { in: KINDS }
  validates :threshold, numericality: true
end
