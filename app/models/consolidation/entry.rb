# A consolidation entry: an elimination or an adjustment on the HEADINGS of the consolidated statements. It is balanced (debits = credits), it belongs to a run,
# it carries its reason and, for the guided manual ones, a supporting document (F03). It lives apart from the books of every company and changes none of them.
class Consolidation::Entry < ApplicationRecord
  KINDS = %w[intragroup_balances intragroup_flows dividends participation intercompany_adjustment adjustment].freeze
  DOCUMENT_REQUIRED = %w[dividends participation].freeze # guided manual entries: the supporting document is compulsory

  acts_as_tenant :entity

  belongs_to :run, class_name: "Consolidation::Run", foreign_key: :consolidation_run_id, inverse_of: :entries
  belongs_to :document, class_name: "Accounting::Document", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :lines, class_name: "Consolidation::EntryLine", foreign_key: :consolidation_entry_id, inverse_of: :entry, dependent: :destroy

  validates :kind, inclusion: { in: KINDS }
  validates :comment, presence: true
  validates :document, presence: { message: "is required: attach the supporting document" }, if: -> { DOCUMENT_REQUIRED.include?(kind) }
  validate :balanced, :run_is_a_draft

  def total = lines.select { |l| l.side == "debit" }.sum(BigDecimal("0")) { |l| l.amount }

  # The change an entry makes to each heading: a line on the side of the heading adds, on the other side subtracts.
  def deltas
    lines.each_with_object(Hash.new(BigDecimal("0"))) { |line, deltas| deltas[line.code] += line.effect }
  end

  private

  def balanced
    debit = lines.select { |l| l.side == "debit" }.sum(BigDecimal("0")) { |l| l.amount }
    credit = lines.select { |l| l.side == "credit" }.sum(BigDecimal("0")) { |l| l.amount }
    errors.add(:base, "the entry does not balance: debit #{format('%.2f', debit)}, credit #{format('%.2f', credit)}") unless debit == credit
    errors.add(:base, "an entry needs at least two lines") if lines.reject(&:marked_for_destruction?).size < 2
  end

  def run_is_a_draft
    errors.add(:base, "the run is #{run.status}: its entries are not changed") unless run.nil? || run.draft?
  end
end
