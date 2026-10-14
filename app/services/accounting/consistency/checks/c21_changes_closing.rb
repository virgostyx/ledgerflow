# The variation of an account between two instants is not the sum of the lines validated between them (B03b, invariant I14): checked from the start of the history to now.
# Either the history or a report cannot be trusted until it is understood.
class Accounting::Consistency::Checks::C21ChangesClosing < Accounting::Consistency::Check
  self.check_id = "C21"
  self.severity = "blocking"
  self.title = "A balance does not move as the validated lines say"

  def call
    fiscal_years.flat_map do |fiscal_year|
      from = Accounting::KnownAt.new(Time.current, fiscal_year: fiscal_year).history_start
      closing = Changes::Between.call(fiscal_year: fiscal_year, from: from).closing
      accounts = Accounting::Account.where(id: closing.gaps.keys).index_by(&:id)
      closing.gaps.map do |id, gap|
        finding(subject: accounts.fetch(id), message: "#{accounts.fetch(id).code}: the variation differs from the movements by #{gap.to_s('F')}", fiscal_year: fiscal_year.id, gap: gap)
      end
    end
  end
end
