# Nightly (F04): refreshes the lettering suggestions of every entity, then letters the certain ones where the entity asked for it.
class Accounting::SuggestLetteringsJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each do |entity|
      ActsAsTenant.with_tenant(entity) do
        Accounting::SuggestLetterings.call
        Accounting::AutoLetterExact.call
      end
    end
  end
end
