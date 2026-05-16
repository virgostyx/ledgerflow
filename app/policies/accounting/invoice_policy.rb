class Accounting::InvoicePolicy < ApplicationPolicy
  def destroy?
    user.admin? || user.accountant?
  end

  def post?
    user.admin? || user.accountant?
  end

  def send_peppol?
    user.admin? || user.accountant?
  end
end
