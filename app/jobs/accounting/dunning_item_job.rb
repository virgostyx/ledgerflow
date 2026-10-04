# Delivers one validated reminder (F09). Takes ids, not records: a job runs with no tenant.
class Accounting::DunningItemJob < ApplicationJob
  queue_as :default

  def perform(item_id, user_id = nil)
    item = ActsAsTenant.without_tenant { Accounting::DunningItem.find(item_id) }
    ActsAsTenant.with_tenant(item.entity) { Accounting::DeliverDunningItem.call(item: item, user: (User.find(user_id) if user_id)) }
  end
end
