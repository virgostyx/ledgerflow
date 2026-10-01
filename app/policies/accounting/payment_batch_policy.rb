class Accounting::PaymentBatchPolicy < ApplicationPolicy
  def generate?
    entity_accountant?
  end

  def execute?
    entity_accountant?
  end

  def download?
    entity_accountant?
  end

  def destroy?
    entity_accountant?
  end
end
