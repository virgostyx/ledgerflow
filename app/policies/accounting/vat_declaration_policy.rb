class Accounting::VatDeclarationPolicy < ApplicationPolicy
  def submit?
    can?("vat.file")
  end

  def accept?
    can?("vat.file")
  end

  def intervat_xml?
    show?
  end
end
