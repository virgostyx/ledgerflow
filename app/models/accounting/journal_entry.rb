class Accounting::JournalEntry < ApplicationRecord
  self.table_name = "accounting_journal_entries"

  include Accounting::Statusable
  include Accounting::Immutable
  include Accounting::Auditable

  belongs_to :journal,     class_name: "Accounting::Journal"
  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear"
  has_many   :lines,       class_name: "Accounting::JournalEntryLine",
                           foreign_key: :journal_entry_id,
                           inverse_of: :journal_entry,
                           dependent: :destroy

  accepts_nested_attributes_for :lines, allow_destroy: true,
    reject_if: proc { |attrs| attrs["account_id"].blank? }

  validates :entry_date, presence: true
  validates :reference,  presence: true, unless: :draft?
  validates :reference,  uniqueness: { case_sensitive: false }, allow_nil: true

  scope :for_fiscal_year, ->(fy) { where(fiscal_year: fy) }
end
