module Entities
  module Actions
    class CreateDefaultAnalyticalAxes
      extend LightService::Action

      expects :entity

      executed do |ctx|
        ActsAsTenant.with_tenant(ctx.entity) do
          Seeders::AnalyticalAxesSeeder.call
        end
      rescue StandardError => e
        ctx.fail!("Failed to create default analytical axes: #{e.message}")
      end
    end
  end
end
