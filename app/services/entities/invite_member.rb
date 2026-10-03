# Gives a person access to an entity. A new email gets an account with a random password nobody knows, and the
# standard "choose your password" mail (Devise recoverable): that is the invitation. An existing account just
# gains the access. Whoever already has an access (even a deactivated one) is refused: change that access instead.
class Entities::InviteMember
  def self.call(entity:, invited_by:, email:, full_name:, role:, valid_until: nil)
    ctx = LightService::Context.make(membership: nil)
    email = email.to_s.strip.downcase
    return ctx.tap { |c| c.fail!(I18n.t("entities.invite.bad_role")) } unless UserEntity.roles.key?(role.to_s)
    return ctx.tap { |c| c.fail!(I18n.t("entities.invite.bad_email")) } unless email.match?(URI::MailTo::EMAIL_REGEXP)

    new_user = nil
    ApplicationRecord.transaction(requires_new: true) do # a refused access takes the account created for it back
      user = User.find_by(email: email)
      new_user = user.nil?
      user ||= User.create!(email: email, full_name: full_name.presence || email, role: :auditor, password: SecureRandom.hex(24))
      Current.set(user: invited_by) do
        ctx[:membership] = ActsAsTenant.with_tenant(entity) do
          UserEntity.create!(user: user, entity: entity, role: role, valid_until: valid_until.presence)
        end
      end
    end
    ctx[:membership].user.send_reset_password_instructions if new_user
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.record.errors.full_messages.to_sentence)
    ctx
  end
end
