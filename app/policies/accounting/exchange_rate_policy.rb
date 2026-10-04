# Exchange rates (F11): seen by whoever sees the records; typed by hand only by those who may override the official rates (`rates.override`).
class Accounting::ExchangeRatePolicy < ApplicationPolicy
  def index?   = can?("records.view")
  def create?  = can?("rates.override")
  def destroy? = create?
end
