class Accounting::FiscalYearPolicy < ApplicationPolicy
  def close?
    can?("fiscal_years.manage")
  end

  def create?
    can?("fiscal_years.manage")
  end

  def new?
    create?
  end

  def update?
    can?("fiscal_years.manage")
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def propose_revaluation?
    can?("closing.adjust")
  end

  def vat_regularization?
    can?("vat.file")
  end
end
