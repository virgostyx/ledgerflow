# Nightly (F04): refreshes the lettering suggestions of every entity.
class Accounting::SuggestLetteringsJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each { |entity| ActsAsTenant.with_tenant(entity) { Accounting::SuggestLetterings.call } }
  end
end
