module ConsolidationHelper
  # What the person may do here in the consolidation: the rights of their role in this company (Accounting::ConsolidationPolicy).
  def consolidation_can?(action) = Accounting::ConsolidationPolicy.new(current_user, nil).public_send(action)
end
