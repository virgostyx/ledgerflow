module Entities
  class ProvisionEntity
    extend LightService::Organizer

    def self.call(entity:, created_by:)
      with(entity: entity, created_by: created_by).reduce(
        Actions::CreateAdminMembership,
        Actions::CopyPcmnChart,
        Actions::CreateDefaultJournals,
        Actions::CreateDefaultAnalyticalAxes,
        Actions::CreateOpenFiscalYear
      )
    end
  end
end
