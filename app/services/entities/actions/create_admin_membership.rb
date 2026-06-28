module Entities
  module Actions
    class CreateAdminMembership
      extend LightService::Action

      expects :entity, :created_by

      executed do |ctx|
        UserEntity.create!(
          user:   ctx.created_by,
          entity: ctx.entity,
          role:   :admin,
          active: true
        )
      rescue StandardError => e
        ctx.fail!("Failed to create admin membership: #{e.message}")
      end
    end
  end
end
