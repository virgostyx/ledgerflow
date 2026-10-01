class Accounting::InvoicePolicy < ApplicationPolicy
  def destroy?
    user.admin? || user.accountant?
  end

  def post?
    user.admin? || user.accountant?
  end

  # An invoice received from BudgetFlow is undone by returning it (reverse + tell BudgetFlow), never by cancelling alone.
  def cancel?
    (user.admin? || user.accountant?) && !from_budgetflow?
  end

  # A draft or posted invoice received from BudgetFlow, for an entity that uses it: the accountant sends it back with a reason.
  def return_to_sender?
    (user.admin? || user.accountant?) && (record.draft? || record.posted?) && from_budgetflow?
  end

  def duplicate?
    create?
  end

  def send_email?
    user.admin? || user.accountant?
  end

  def pdf?
    show?
  end

  def create_credit_note?
    user.admin? || user.accountant?
  end

  def apply_credit_note?
    user.admin? || user.accountant?
  end

  def send_peppol?
    user.admin? || user.accountant?
  end

  private

  def from_budgetflow?
    record.respond_to?(:external_digest) && record.external_digest.present? && ActsAsTenant.current_tenant&.budgetflow? == true
  end
end
