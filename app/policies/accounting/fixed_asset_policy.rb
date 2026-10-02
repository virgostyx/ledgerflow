class Accounting::FixedAssetPolicy < ApplicationPolicy
  # These validate entries: reserved to those who may post (an assistant only drafts).
  def post_depreciation? = can?("entries.post")
  def disposal? = can?("entries.post")
  def dispose? = can?("entries.post")
end
