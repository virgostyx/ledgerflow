# B03b: the last time a person opened the report of changes of the company. It only proposes the default T1; it is the person's own, shown to them and erasable.
class Accounting::UserVisit < ApplicationRecord
  self.table_name = "accounting_user_visits"

  acts_as_tenant :entity

  belongs_to :user
end
