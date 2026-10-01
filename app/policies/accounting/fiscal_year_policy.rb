class Accounting::FiscalYearPolicy < ApplicationPolicy
  def close?
    entity_admin?
  end

  def create?
    entity_admin?
  end

  def new?
    create?
  end

  def update?
    entity_admin?
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def propose_revaluation?
    entity_accountant?
  end

  def vat_regularization?
    entity_accountant?
  end
end
