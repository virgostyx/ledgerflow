class Accounting::VatDeclarationPolicy < ApplicationPolicy
  def submit?
    entity_accountant?
  end

  def accept?
    entity_accountant?
  end

  def intervat_xml?
    show?
  end
end
