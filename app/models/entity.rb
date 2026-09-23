class Entity < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :user_entities, dependent: :destroy
  has_many :users, through: :user_entities

  enum :vat_filing_frequency, { monthly: 0, quarterly: 1 }
  enum :vat_regime,           { normal: 0, franchise: 1 }

  validates :name,       presence: true
  validates :legal_name, presence: true
  validates :country,    presence: true
  validates :vat_number, uniqueness: true, allow_blank: true

  scope :active, -> { where(active: true) }
end
