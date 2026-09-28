# A closing regularization (docs/dev/reports/spec.md §13, R17): a deferral (charge/income belonging to a
# later period) or an accrual (charge/income earned but not yet invoiced) at a cut-off date, with the link
# to its source document, the journal entry it generated and that entry's reversal.
class Accounting::Accrual < ApplicationRecord
  self.table_name = "accounting_accruals"

  acts_as_tenant :entity

  enum :accrual_type, { deferred_charge: 0, accrued_income: 1, accrued_charge: 2, deferred_income: 3 }

  # Account of the chart used by default per type. The chart seeds "Produits acquis" and "Produits à reporter"
  # under 4902xx and 4922xx (the official PCMN uses 491 and 493); the labels decide, see QUESTIONS.md.
  ACCOUNT_CODES = { deferred_charge: "490100", accrued_income: "490200", accrued_charge: "492100", deferred_income: "492200" }.freeze
  DEFERRALS = %i[deferred_charge deferred_income].freeze

  belongs_to :fiscal_year,     class_name: "Accounting::FiscalYear"
  belongs_to :pl_account,      class_name: "Accounting::Account"
  belongs_to :accrual_account, class_name: "Accounting::Account"
  belongs_to :source_journal_entry, class_name: "Accounting::JournalEntry", optional: true
  belongs_to :journal_entry,   class_name: "Accounting::JournalEntry", optional: true
  belongs_to :reversal_entry,  class_name: "Accounting::JournalEntry", optional: true

  validates :description, presence: true
  validates :total_amount, numericality: { greater_than: 0 }
  validates :period_start, :period_end, presence: true
  validate  :period_in_order

  def deferral? = DEFERRALS.include?(accrual_type.to_sym)

  def booked? = journal_entry_id.present?

  # Deferral: total × days after the cut-off ÷ days of the period. Accrual: total × days elapsed up to the
  # cut-off ÷ days of the period (the share of the service already rendered). Rounded to the cent.
  def amount_at(cut_off)
    total_days = (period_end - period_start).to_i + 1
    days = if deferral?
      (period_end - cut_off).to_i.clamp(0, total_days)
    else
      ((cut_off - period_start).to_i + 1).clamp(0, total_days)
    end
    (total_amount * days / total_days).round(2)
  end

  private

  def period_in_order
    errors.add(:period_end, "must not be before the start") if period_start && period_end && period_end < period_start
  end
end
