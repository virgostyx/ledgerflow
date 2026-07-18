class Accounting::StatusPresenter
  LABELS = {
    draft:     "Draft",
    posted:    "Posted",
    reversed:  "Cancelled",
    paid:      "Paid",
    cancelled: "Cancelled",
    generated: "Generated",
    executed:  "Executed"
  }.freeze

  BADGE_VARIANTS = {
    draft:     :default,
    posted:    :success,
    reversed:  :danger,
    paid:      :success,
    cancelled: :danger,
    generated: :warning,
    executed:  :success
  }.freeze

  def initialize(status)
    @status = status.to_sym
  end

  def label
    LABELS.fetch(@status, @status.to_s)
  end

  def badge_variant
    BADGE_VARIANTS.fetch(@status, :default)
  end
end
