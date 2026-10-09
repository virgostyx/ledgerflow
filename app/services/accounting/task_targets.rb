# What a task or a comment can be about (F08), and who may see it: whoever sees the thing sees its tasks and comments. A ledger line is seen like its
# entry (an access limited to some journals does not reach the lines of the others).
module Accounting::TaskTargets
  TYPES = %w[Accounting::JournalEntry Accounting::JournalEntryLine Accounting::Account Accounting::Partner Accounting::Document
             Accounting::BankTransaction Accounting::PeriodLock Accounting::Invoice].freeze

  POLICIES = { "Accounting::JournalEntry" => Accounting::JournalEntryPolicy, "Accounting::JournalEntryLine" => Accounting::JournalEntryPolicy,
               "Accounting::Partner" => Accounting::PartnerPolicy, "Accounting::Document" => Accounting::DocumentPolicy,
               "Accounting::BankTransaction" => Accounting::BankStatementPolicy, "Accounting::Invoice" => Accounting::InvoicePolicy }.freeze

  # The entry a target belongs to (for the badge of the entry), or nil.
  def self.entry_of(target)
    case target
    when Accounting::JournalEntry then target
    when Accounting::JournalEntryLine then target.journal_entry
    end
  end

  # Of this entity, of a known type, and shown to this user by the policy of that type (an account and a period by the general right to read records).
  def self.visible?(user, target)
    return false unless user && target && TYPES.include?(target.class.name) && target.entity_id == ActsAsTenant.current_tenant&.id

    policy_class(target.class.name).new(user, entry_of(target) || target).show?
  end

  # What a comment is about, seen by this user: a task as `Accounting::Task.visible_to` says (a task about nothing is seen by those it concerns), anything
  # else as `visible?` says.
  def self.visible_commentable?(user, commentable)
    return Accounting::Task.visible_to(user).exists?(commentable.id) if commentable.is_a?(Accounting::Task)

    visible?(user, commentable)
  end

  # The types of target the user may see at all (a custom role can take away the right to read records), for the list of tasks.
  def self.visible_types(user)
    TYPES.select { |type| policy_class(type).new(user, type.constantize.new).show? }
  end

  def self.policy_class(type) = POLICIES.fetch(type, ApplicationPolicy)
end
