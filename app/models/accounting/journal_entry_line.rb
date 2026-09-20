class Accounting::JournalEntryLine < ApplicationRecord
  self.table_name = "accounting_journal_entry_lines"

  acts_as_tenant :entity

  include Accounting::MonetaryPrecision

  belongs_to :journal_entry, class_name: "Accounting::JournalEntry",
                             inverse_of: :lines
  belongs_to :account,       class_name: "Accounting::Account"
  belongs_to :partner,       class_name: "Accounting::Partner",
                              foreign_key: :partner_id, optional: true
  belongs_to :invoice,       class_name: "Accounting::Invoice", optional: true
  belongs_to :lettering,     class_name: "Accounting::Lettering", optional: true, inverse_of: :lines
  has_many   :analytical_annotations, class_name: "Accounting::AnalyticalAnnotation",
             foreign_key: :journal_entry_line_id, inverse_of: :journal_entry_line,
             dependent: :destroy

  accepts_nested_attributes_for :analytical_annotations,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["analytical_account_id"].blank? && attrs["id"].blank? }

  MONETARY_COLUMNS = %w[debit credit vat_amount amount_currency].freeze

  validate :partner_belongs_to_entity
  validate :only_one_side_positive
  validate :at_least_one_side_positive

  private

  # The association is tenant-scoped, so a partner id from another entity resolves to nil.
  def partner_belongs_to_entity
    errors.add(:partner, :invalid) if partner_id.present? && partner.nil?
  end

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
