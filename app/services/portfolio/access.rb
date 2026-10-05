# F12a: who sees which entity in the portfolio. Always and only through the membership of the entity (current, in its validity window), whatever the
# organization says; and only the entities that turned the feature on. What a person may DO in a dossier is the right their role gives in that dossier.
class Portfolio::Access
  # => the entities of the portfolio of `user`
  def self.entities(user)
    user.current_entities.active.where("entities.features @> ?", { "f12" => true }.to_json)
  end

  def self.membership(user, entity) = UserEntity.current.find_by(user_id: user.id, entity_id: entity.id)

  def self.allowed?(user, entity, permission) = membership(user, entity)&.allows?(permission) || false

  def self.owner?(user, entity) = membership(user, entity)&.owner? || false
end
