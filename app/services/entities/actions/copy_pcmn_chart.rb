module Entities
  module Actions
    class CopyPcmnChart
      extend LightService::Action

      expects :entity

      executed do |ctx|
        ActsAsTenant.with_tenant(ctx.entity) do
          Seeders::PcmnSeeder.call
        end
      rescue StandardError => e
        ctx.fail!("Failed to copy PCMN chart: #{e.message}")
      end
    end
  end
end
