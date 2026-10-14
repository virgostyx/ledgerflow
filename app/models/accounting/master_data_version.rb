# B03a: one version of an account or a partner (what is shown of it), written by the database when it is created or one of those values changes. Never changed.
class Accounting::MasterDataVersion < ApplicationRecord
  self.table_name = "accounting_master_data_versions"

  acts_as_tenant :entity
end
