class Accounting::InvoicePolicy < ApplicationPolicy
  def destroy?
    user.admin? || user.accountant?
  end

  def post?
    user.admin? || user.accountant?
  end

  def cancel?
    user.admin? || user.accountant?
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
end
