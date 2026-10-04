# A model of journal entry (F07): a journal, a description and model lines. Accounting::BuildEntryFromTemplate turns it into a draft entry;
# a recurring entry builds one at each due date. Variables in the description and labels: {mois}/{month}, {année}/{year},
# {période}/{period}, filled from the date of the entry.
class Accounting::EntryTemplate < ApplicationRecord
  include Accounting::AuditTrailed
  self.table_name = "accounting_entry_templates"

  acts_as_tenant :entity

  belongs_to :journal, class_name: "Accounting::Journal"
  has_many :lines, -> { order(:position, :id) }, class_name: "Accounting::EntryTemplateLine", foreign_key: :entry_template_id,
                                                inverse_of: :entry_template, dependent: :destroy
  has_many :recurring_entries, class_name: "Accounting::RecurringEntry", foreign_key: :entry_template_id, inverse_of: :entry_template, dependent: :restrict_with_error

  accepts_nested_attributes_for :lines, allow_destroy: true, reject_if: proc { |attrs| attrs["account_id"].blank? }

  validates :name, presence: true, uniqueness: { scope: :entity_id, case_sensitive: false }
  validate  :at_least_two_lines

  def needs_base? = lines.any?(&:percent?)

  def input_lines = lines.select(&:input?)

  # A recurring entry in post mode may only run a template whose every amount is known in advance.
  def fixed_amounts_only? = input_lines.empty?

  def self.interpolate(text, date)
    text.to_s.gsub(/\{(mois|month)\}/, I18n.l(date, format: "%B")).gsub(/\{(année|year)\}/, date.year.to_s)
        .gsub(/\{(période|period)\}/, I18n.l(date, format: "%B %Y"))
  end

  private

  def at_least_two_lines
    errors.add(:base, "A template needs at least two lines") if lines.reject(&:marked_for_destruction?).size < 2
  end
end
