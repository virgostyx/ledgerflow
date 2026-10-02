class Accounting::PaymentBatchPolicy < ApplicationPolicy
  def generate?
    can?("payments.manage")
  end

  def execute?
    can?("payments.manage")
  end

  def download?
    can?("payments.manage")
  end

  def destroy?
    can?("payments.manage")
  end
end
