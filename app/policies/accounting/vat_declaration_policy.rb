class Accounting::VatDeclarationPolicy < ApplicationPolicy
  def submit?
    user.admin? || user.accountant?
  end

  def accept?
    user.admin? || user.accountant?
  end

  def intervat_xml?
    show?
  end
end
