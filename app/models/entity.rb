class Entity < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :user_entities, dependent: :destroy
  has_many :users, through: :user_entities

  enum :vat_filing_frequency, { monthly: 0, quarterly: 1 }
  enum :vat_regime,           { normal: 0, franchise: 1 }
  enum :vat_scheme,           { normal: 0, mixed: 1 }, prefix: :vat_scheme

  # A blank number must be NULL: the unique index on vat_number only skips NULLs.
  normalizes :vat_number, with: ->(number) { number.strip.presence }

  validates :name,       presence: true
  validates :legal_name, presence: true
  validates :country,    presence: true
  validates :vat_number, uniqueness: true, allow_blank: true
  validate  :vat_number_format

  scope :active, -> { where(active: true) }

  private

  def vat_number_format
    errors.add(:vat_number, :invalid) unless vat_number.blank? || Accounting::Partner.valid_vat_number?(vat_number)
  end
end
