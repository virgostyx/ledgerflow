class Accounting::InvoicePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve = in_allowed_journals
  end

  def show?   = super && journal_allowed?
  def create? = super && journal_allowed?
  def update? = super && journal_allowed?

  def destroy?
    can?("invoices.issue") && journal_allowed?
  end

  def post?
    can?("invoices.issue") && journal_allowed?
  end

  # An invoice received from BudgetFlow is undone by returning it (reverse + tell BudgetFlow), never by cancelling alone.
  def cancel?
    (can?("invoices.issue")) && !from_budgetflow?
  end

  # A draft or posted invoice received from BudgetFlow, for an entity that uses it: the accountant sends it back with a reason.
  def return_to_sender?
    (can?("invoices.issue")) && (record.draft? || record.posted?) && from_budgetflow?
  end

  def duplicate?
    create?
  end

  def send_email?
    can?("invoices.issue")
  end

  def pdf?
    show?
  end

  def create_credit_note?
    can?("invoices.issue")
  end

  def apply_credit_note?
    can?("invoices.issue")
  end

  def send_peppol?
    can?("peppol.send")
  end

  private

  def from_budgetflow?
    record.respond_to?(:external_digest) && record.external_digest.present? && ActsAsTenant.current_tenant&.budgetflow? == true
  end
end
