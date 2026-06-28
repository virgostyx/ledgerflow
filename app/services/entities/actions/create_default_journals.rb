module Entities
  module Actions
    class CreateDefaultJournals
      extend LightService::Action

      expects :entity

      executed do |ctx|
        ActsAsTenant.with_tenant(ctx.entity) do
          Seeders::JournalsSeeder.call
        end
      rescue StandardError => e
        ctx.fail!("Failed to create default journals: #{e.message}")
      end
    end
  end
end
