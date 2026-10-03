# A rule of the entity for bank lines (F02, rule 6 of the matching engine): when the line says this (contains a text, comes from
# this IBAN, has this amount), it is booked on this account (and partner). `propose` only suggests it with `score`;
# `book_draft` has the engine book it as a draft entry.
class Accounting::BankRule < ApplicationRecord
  self.table_name = "accounting_bank_rules"

  CONDITIONS = %w[contains iban amount].freeze
  ACTIONS = %w[propose book_draft].freeze

  acts_as_tenant :entity

  belongs_to :account, class_name: "Accounting::Account"
  belongs_to :partner, class_name: "Accounting::Partner", optional: true

  validates :name, :condition_value, presence: true
  validates :condition_type, inclusion: { in: CONDITIONS }
  validates :action, inclusion: { in: ACTIONS }
  validates :score, numericality: { only_integer: true, in: 1..99 } # 100 is for an exact invoice match
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :amount_is_a_number, if: -> { condition_type == "amount" }

  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(:priority, :id) }

  def self.first_match_for(transaction) = active.by_priority.includes(:account, :partner).find { |rule| rule.matches?(transaction) }

  def book_draft? = action == "book_draft"

  def matches?(transaction)
    case condition_type
    when "contains" then plain([ transaction.counterparty_name, transaction.description ].join(" ")).include?(plain(condition_value))
    when "iban"     then normalize_iban(transaction.counterparty_iban) == normalize_iban(condition_value)
    when "amount"   then number(condition_value) == transaction.amount
    end
  end

  # What a line says, to build a rule from it: its counterparty's IBAN, else a piece of its text.
  def self.from_line(transaction, account:, **attrs)
    if transaction.counterparty_iban.present?
      new(condition_type: "iban", condition_value: transaction.counterparty_iban, account: account, **attrs)
    else
      new(condition_type: "contains", condition_value: (transaction.counterparty_name.presence || transaction.description).to_s.strip.first(60), account: account, **attrs)
    end
  end

  private

  def plain(text) = I18n.transliterate(text.to_s).downcase.squish
  def normalize_iban(text) = text.to_s.delete(" ").upcase
  def number(text) = BigDecimal(text.to_s.tr(",", "."), exception: false)

  def amount_is_a_number
    errors.add(:condition_value, :not_a_number) unless number(condition_value)
  end
end
