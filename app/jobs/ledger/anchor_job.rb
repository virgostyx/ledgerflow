# Nightly (B03c): the anchor of the day of each company.
class Ledger::AnchorJob < ApplicationJob
  queue_as :default

  def perform = Ledger::NightlyAnchoring.call
end
