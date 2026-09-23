class Accounting::FiscalYearPolicy < ApplicationPolicy
  def close?
    user.admin?
  end

  def create?
    user.admin?
  end

  def new?
    create?
  end

  def update?
    user.admin?
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def vat_regularization?
    user.admin? || user.accountant?
  end
end
