# Who is asking the agent, about which entity, when and from where (A01). Built by the server for every question and never changed afterwards: the
# entity and the person are not arguments the model can give or alter (A03). The rights are read again at every call, not kept from the start of the talk.
Agent::Context = Data.define(:user, :entity, :locale, :today, :screen, :subject_ref) do
  def self.build(user:, entity:, locale:, screen: nil, subject_ref: {}, today: Date.current)
    new(user: user, entity: entity, locale: locale.to_sym, today: today, screen: screen, subject_ref: subject_ref.to_h.freeze)
  end

  # A permission of Permissions::MATRIX, as the membership holds it now. An unknown permission raises: a typo is a bug, not a denial.
  def allows?(permission)
    membership = UserEntity.current.find_by(user: user, entity: entity)
    membership ? membership.allows?(permission) : Permissions.allowed?(nil, permission)
  end
end
