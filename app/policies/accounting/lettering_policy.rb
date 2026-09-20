class Accounting::LetteringPolicy < ApplicationPolicy
  def destroy? = create?
end
