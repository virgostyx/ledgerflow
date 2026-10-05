# F13b: a backup is kept a few days; then the file goes (it holds the whole books), and the line stays to say it was made.
class Exports::PurgeExpiredJob < ApplicationJob
  queue_as :default

  def perform
    DataExport.unscoped.stale.find_each do |export|
      export.file.purge
      export.update!(status: "expired")
    end
  end
end
