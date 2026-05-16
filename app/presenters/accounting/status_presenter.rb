class Accounting::StatusPresenter
  LABELS = {
    draft:    "Draft",
    posted:   "Posted",
    reversed: "Cancelled"
  }.freeze

  BADGE_VARIANTS = {
    draft:    :default,
    posted:   :success,
    reversed: :danger
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
