# Tells a person that their summary is ready (A10a): in the application always (the bell), by e-mail if they asked. The e-mail carries counts and links; the entity may allow details in it.
module Agent::Digest::Deliver
  def self.call(digest)
    ActsAsTenant.with_tenant(digest.entity) do
      Accounting::Notify.call(user: digest.user, event: "agent_digest:#{digest.id}", subject: digest, data: { "message" => "#{digest.item_count} point(s) need your attention" })
      preference = Agent::DigestPreference.find_by(user_id: digest.user_id)
      Agent::DigestMailer.summary(digest, details: Agent::Setting.find_by(entity: digest.entity)&.digest_email_details == true).deliver_later if preference&.email
    end
    digest
  end
end
