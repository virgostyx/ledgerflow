# F12b: who may consolidate or read a consolidation: a person with a current membership in the PARENT and in EVERY member company, and every one of those
# companies has turned the feature on. Anything less is a refusal of the whole: a consolidation is never partial, and what a person could not read alone is
# never shown to them as part of a total.
module Consolidation::Access
  # => the number of companies of the group (parent included) the person has no access to, or that did not turn the feature on
  def self.missing(user, group)
    entity_ids = ([ group.entity_id ] + group.members.map(&:member_entity_id)).uniq
    reachable = UserEntity.current.where(user_id: user.id, entity_id: entity_ids).pluck(:entity_id)
    ready = Entity.where(id: entity_ids).where("features @> ?", { "f12" => true }.to_json).pluck(:id)
    (entity_ids - (reachable & ready)).size
  end

  def self.all_members?(user, group) = missing(user, group).zero?
end
