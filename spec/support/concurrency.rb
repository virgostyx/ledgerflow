# Concurrency specs (F01 review): real threads, each on its own database connection, so the examples tagged
# `concurrency` cannot run inside the usual rolled-back transaction: they truncate instead (reference data kept).
module ConcurrencyHelpers
  # Runs the blocks at the same moment, each in its own thread and connection, inside the entity. => their results
  def concurrently(*blocks, entity:)
    ready = Queue.new
    go    = Queue.new
    threads = blocks.map do |block|
      Thread.new do
        signalled = false
        begin
          ActiveRecord::Base.connection_pool.with_connection do
            ActsAsTenant.with_tenant(entity) do
              ready << true
              signalled = true
              go.pop(timeout: 30)
              block.call
            end
          end
        ensure
          ready << true unless signalled # never leave the starter waiting
        end
      end
    end
    blocks.size.times { ready.pop(timeout: 15) }
    blocks.size.times { go << true }
    threads.map { |thread| thread.join(30) ? thread.value : raise("a concurrent block did not finish in 30 s (deadlock?)") }
  end
end

RSpec.configure { |config| config.include ConcurrencyHelpers, :concurrency }
