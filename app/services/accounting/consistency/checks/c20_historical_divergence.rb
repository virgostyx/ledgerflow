# The history of the books does not reproduce a snapshot that was frozen (B03a): recomputed at the instant of the snapshot, the books give other figures. Either the history
# cannot be trusted or the snapshot was changed; either way nothing that depends on a past view can be relied on until it is understood.
class Accounting::Consistency::Checks::C20HistoricalDivergence < Accounting::Consistency::Check
  self.check_id = "C20"
  self.severity = "blocking"
  self.title = "The history does not reproduce a frozen snapshot"

  def call
    TimeTravel::WitnessCheck.call(fiscal_year: @fiscal_year).map do |divergence|
      subject = divergence.witness_type.constantize.find(divergence.witness_id)
      finding(subject: subject, message: "#{divergence.witness_type.demodulize.underscore.humanize.downcase} ##{divergence.witness_id}: #{divergence.detail}", witness: divergence.witness_type)
    end
  end
end
