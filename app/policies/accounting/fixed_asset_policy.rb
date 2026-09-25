class Accounting::FixedAssetPolicy < ApplicationPolicy
  def post_depreciation? = create?
end
