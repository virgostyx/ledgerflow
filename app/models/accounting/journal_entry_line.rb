class Accounting::JournalEntryLine < ApplicationRecord
  self.table_name = "accounting_journal_entry_lines"

  include Accounting::MonetaryPrecision

  belongs_to :journal_entry, class_name: "Accounting::JournalEntry",
                             inverse_of: :lines
  belongs_to :account,       class_name: "Accounting::Account"
  belongs_to :partner,       class_name: "Accounting::Partner",
                              foreign_key: :partner_id, optional: true
  has_many   :analytical_annotations, class_name: "Accounting::AnalyticalAnnotation",
             foreign_key: :journal_entry_line_id, inverse_of: :journal_entry_line,
             dependent: :destroy

  accepts_nested_attributes_for :analytical_annotations,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["analytical_account_id"].blank? && attrs["id"].blank? }

  MONETARY_COLUMNS = %w[debit credit vat_amount amount_currency].freeze

  validate :only_one_side_positive
  validate :at_least_one_side_positive

  private

  def only_one_side_positive
    return unless debit.present? && credit.present?
    return unless debit > 0 && credit > 0

    errors.add(:base, I18n.t("accounting.errors.dual_side"))
  end

  def at_least_one_side_positive
    return unless debit.present? && credit.present?
    return unless debit <= 0 && credit <= 0

    errors.add(:base, I18n.t("accounting.errors.zero_side"))
  end
end
