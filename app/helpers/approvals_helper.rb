# How the approvals table writes a duration given in hours: "3.3 h", then days from two days up; nothing when there is nothing to average.
module ApprovalsHelper
  def approval_hours(hours)
    return "—" if hours.nil?

    hours < 48 ? "#{hours.to_f.round(1)} h" : "#{(hours.to_f / 24).round(1)} days"
  end

  def approval_percent(rate) = rate.nil? ? "—" : "#{(rate * 100).round} %"
end
