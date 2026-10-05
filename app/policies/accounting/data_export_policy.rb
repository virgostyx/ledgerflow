# Data exports (F13b): whoever has `exports.data` downloads the standard files; the full backup, which holds every document and the audit trail,
# is the owner's (`exports.backup`). A read-only role does not export data, whatever the entity allows for reports.
class Accounting::DataExportPolicy < ApplicationPolicy
  def index?  = can?("exports.data")
  def create? = can?("exports.data")
  def backup? = can?("exports.backup")
end
