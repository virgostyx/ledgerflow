# Which ledger lines the dunning follow-up (dispute, promise) is about: those of the customer accounts, as R04 and R05 read them.
module Accounting::DunningLines
  def self.customer_line?(line) = line.account.reconcilable && line.account.code.start_with?(Accounting::OpenLineSql::PREFIX.fetch(:customer).delete("%"))
end
