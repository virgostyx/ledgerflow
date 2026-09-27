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

  # Denormalized from journal_entry.entry_date (docs/dev/reports/spec.md §3), so
  # reports can filter/index lines by date without joining accounting_journal_entries.
  # before_save (not before_validation): must run even when a save skips validation
  # (e.g. the balanced-lines factories, which defer the double-entry DB check).
  before_save :sync_entry_date
  before_create :init_amount_residual

  validate :partner_belongs_to_entity
  validate :only_one_side_positive
  validate :at_least_one_side_positive

  def allocations = Accounting::LineAllocation.touching(id)

  # Unsigned amount still to settle: the line's amount minus what partial lettering already allocated to it.
  def open_amount = debit + credit - allocations.sum(:amount)

  # Recomputes and persists amount_residual for the given line ids in one UPDATE.
  # Called explicitly by the lettering/allocation services (docs/dev/reports/spec.md §7):
  # they change lettering_id / accounting_line_allocations via update_all/nullify/destroy_all,
  # which bypass AR callbacks, so no model callback here could catch these changes.
  def self.resync_amount_residual!(ids)
    ids = Array(ids).map(&:to_i)
    return if ids.empty?

    connection.execute(<<~SQL)
      UPDATE accounting_journal_entry_lines l
      SET amount_residual = CASE
        WHEN l.lettering_id IS NOT NULL THEN 0
        ELSE l.debit + l.credit - COALESCE((
          SELECT SUM(al.amount) FROM accounting_line_allocations al
          WHERE al.debit_line_id = l.id OR al.credit_line_id = l.id
        ), 0)
      END
      WHERE l.id IN (#{ids.join(',')})
    SQL
  end

  private

  def sync_entry_date
    self.entry_date = journal_entry&.entry_date
  end

  def init_amount_residual
    self.amount_residual = debit + credit
  end

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
