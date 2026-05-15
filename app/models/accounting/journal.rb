class Accounting::Journal < ApplicationRecord
  self.table_name = "accounting_journals"

  enum :journal_type, { purchase: 0, sale: 1, bank: 2, cash: 3, misc: 4, payroll: 5 }

  belongs_to :default_account, class_name: "Accounting::Account",
             foreign_key: :default_account_id, optional: true

  validates :code,             presence: true, uniqueness: true,
                               length: { maximum: 5 }
  validates :label_fr,         presence: true
  validates :journal_type,     presence: true
  validates :sequence_prefix,  presence: true

  scope :active, -> { where(active: true) }

  def next_sequence_number(year:)
    self.class.transaction do
      lock!
      self.current_sequence += 1
      save!
      "#{sequence_prefix}#{year}/#{current_sequence.to_s.rjust(4, '0')}"
    end
  end
end
