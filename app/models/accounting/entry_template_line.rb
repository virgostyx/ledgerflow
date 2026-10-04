# One model line of an entry template: amount fixed, a percentage of the amount asked for the whole entry, or typed when the entry is made.
class Accounting::EntryTemplateLine < ApplicationRecord
  self.table_name = "accounting_entry_template_lines"

  acts_as_tenant :entity

  enum :side,        { debit: 0, credit: 1 }
  enum :amount_kind, { fixed: 0, percent: 1, input: 2 }

  belongs_to :entry_template, class_name: "Accounting::EntryTemplate", inverse_of: :lines
  belongs_to :account, class_name: "Accounting::Account"
  belongs_to :partner, class_name: "Accounting::Partner", optional: true

  validates :amount, numericality: { greater_than: 0 }, if: :fixed?
  validates :percentage, numericality: { greater_than: 0 }, if: :percent?
end
