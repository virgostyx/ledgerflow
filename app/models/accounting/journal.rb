class Accounting::Journal < ApplicationRecord
  self.table_name = "accounting_journals"

  acts_as_tenant :entity

  COUNTERPART_PREFIXES = {
    "bank"     => "55",
    "cash"     => "57",
    "purchase" => "44",
    "sale"     => "40"
  }.freeze

  enum :journal_type, { purchase: 0, sale: 1, bank: 2, cash: 3, misc: 4, payroll: 5 }

  belongs_to :default_account, class_name: "Accounting::Account",
             foreign_key: :default_account_id, optional: true
  has_many :journal_entries, class_name: "Accounting::JournalEntry",
           foreign_key: :journal_id, dependent: :restrict_with_error
  has_one :bank_account, class_name: "Accounting::BankAccount",
          foreign_key: :journal_id, dependent: :nullify

  validates :code,            presence: true, uniqueness: { scope: :entity_id }, length: { maximum: 5 }
  validates :label_fr,        presence: true
  validates :journal_type,    presence: true
  validates :sequence_prefix, presence: true
  validates :default_account_id, presence: true, if: :requires_counterpart_account?

  validate :counterpart_account_matches_journal_type
  validate :code_immutable_after_entries, on: :update

  scope :active, -> { where(active: true) }
  scope :by_type, ->(type) { where(journal_type: type) }

  def requires_counterpart_account?
    bank? || cash? || purchase? || sale?
  end

  def display_name
    "#{code} — #{label_fr}"
  end

  def destroyable?
    journal_entries.none?
  end

  def deactivatable?
    journal_entries.where(status: :draft).none?
  end

  def next_sequence_number(year:)
    self.class.transaction do
      lock!
      self.current_sequence += 1
      save!
      "#{sequence_prefix}#{year}/#{current_sequence.to_s.rjust(4, '0')}"
    end
  end

  private

  def counterpart_account_matches_journal_type
    return unless default_account && requires_counterpart_account?
    expected_prefix = COUNTERPART_PREFIXES[journal_type]
    return if default_account.code.start_with?(expected_prefix)
    errors.add(:default_account_id,
               "must be a #{expected_prefix}xxxx account for a #{journal_type} journal")
  end

  def code_immutable_after_entries
    return unless code_changed? && journal_entries.exists?
    errors.add(:code, "cannot be changed after journal entries have been recorded")
  end
end
