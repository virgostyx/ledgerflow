class Accounting::InvoicePolicy < ApplicationPolicy
  def destroy?
    entity_accountant?
  end

  def post?
    entity_accountant?
  end

  # An invoice received from BudgetFlow is undone by returning it (reverse + tell BudgetFlow), never by cancelling alone.
  def cancel?
    (entity_accountant?) && !from_budgetflow?
  end

  # A draft or posted invoice received from BudgetFlow, for an entity that uses it: the accountant sends it back with a reason.
  def return_to_sender?
    (entity_accountant?) && (record.draft? || record.posted?) && from_budgetflow?
  end

  def duplicate?
    create?
  end

  def send_email?
    entity_accountant?
  end

  def pdf?
    show?
  end

  def create_credit_note?
    entity_accountant?
  end

  def apply_credit_note?
    entity_accountant?
  end

  def send_peppol?
    entity_accountant?
  end

  private

  def from_budgetflow?
    record.respond_to?(:external_digest) && record.external_digest.present? && ActsAsTenant.current_tenant&.budgetflow? == true
  end
end
