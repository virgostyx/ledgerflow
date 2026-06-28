module Entities
  module Actions
    class CreateOpenFiscalYear
      extend LightService::Action

      expects :entity

      executed do |ctx|
        current_year = Date.current.year
        ActsAsTenant.with_tenant(ctx.entity) do
          Accounting::FiscalYear.create!(
            year:       current_year,
            start_date: Date.new(current_year, 1, 1),
            end_date:   Date.new(current_year, 12, 31),
            status:     :open
          )
        end
      rescue StandardError => e
        ctx.fail!("Failed to create fiscal year: #{e.message}")
      end
    end
  end
end
