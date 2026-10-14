# B03a: the database gives one instant to everything one transaction validates, and a spec is one transaction. A spec that needs two validations at two instants asks
# for a new one (the clock itself is the database's, it is never faked).
module PostingClock
  # A point of the clock of the database, with room on both sides: what is done before it is known at it, what is done after it is not.
  def instant
    sleep 0.01
    ApplicationRecord.connection.select_value("SELECT clock_timestamp()").tap { sleep 0.01 }
  end

  def next_posting_instant
    sleep 0.01
    ApplicationRecord.connection.execute("SELECT set_config('ledgerflow.posted_at', '', true)")
  end
end

RSpec.configure { |config| config.include PostingClock }
