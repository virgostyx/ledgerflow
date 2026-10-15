# Nightly and weekly (B03c): the check of the integrity of the books. `mode`: nightly (the last seven days and a sample) or full.
class Integrity::SelfCheckJob < ApplicationJob
  queue_as :default

  def perform(mode = "nightly") = Integrity::SelfCheck.run(mode: mode.to_sym)
end
