class Accounting::PaymentBatchPolicy < ApplicationPolicy
  def generate?
    user.admin? || user.accountant?
  end

  def execute?
    user.admin? || user.accountant?
  end

  def download?
    user.admin? || user.accountant?
  end

  def destroy?
    user.admin? || user.accountant?
  end
end
