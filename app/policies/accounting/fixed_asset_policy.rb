class Accounting::FixedAssetPolicy < ApplicationPolicy
  def post_depreciation? = create?
  def disposal? = update?
  def dispose? = update?
end
