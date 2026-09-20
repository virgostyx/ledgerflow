class Accounting::JournalEntry < ApplicationRecord
  self.table_name = "accounting_journal_entries"

  acts_as_tenant :entity
  broadcasts_refreshes_to ->(r) { [ r.entity, :journal_entries ] }

  include Accounting::Statusable
  include Accounting::Immutable
  include Accounting::Auditable

  belongs_to :journal,     class_name: "Accounting::Journal"
  belongs_to :fiscal_year, class_name: "Accounting::FiscalYear"
  belongs_to :reversal_of, class_name: "Accounting::JournalEntry", optional: true
  has_one    :reversal,    class_name: "Accounting::JournalEntry", foreign_key: :reversal_of_id, inverse_of: :reversal_of
  has_many   :lines,       class_name: "Accounting::JournalEntryLine",
                           foreign_key: :journal_entry_id,
                           inverse_of: :journal_entry,
                           dependent: :destroy

  accepts_nested_attributes_for :lines, allow_destroy: true,
    reject_if: proc { |attrs| attrs["account_id"].blank? }

  validates :entry_date, presence: true
  validates :reference,  presence: true, unless: :draft?
  validates :reference,  uniqueness: { scope: :entity_id, case_sensitive: false }, allow_nil: true

  scope :for_fiscal_year, ->(fy) { where(fiscal_year: fy) }

  def self.filter_by(q)
    matching(status: q[:status], journal_id: q[:journal_id], fiscal_year_id: q[:fiscal_year_id])
      .search(q[:q], "reference", "description")
      .between(:entry_date, q[:from], q[:to])
  end
end
