# F12a: every night, one snapshot job for each entity of the portfolio. The entities are listed from their own table; each job then reads its own books.
class Portfolio::SnapshotAllJob < ApplicationJob
  queue_as :default

  def perform
    Entity.active.where("features @> ?", { "f12" => true }.to_json).pluck(:id).each { |id| Portfolio::SnapshotJob.perform_later(id) }
  end
end
