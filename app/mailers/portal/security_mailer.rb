# Security alerts to the person: sent whatever their preferences. They say when, from where and with what; never a secret.
class Portal::SecurityMailer < ApplicationMailer
  def new_device(user, device)
    @name = user.full_name
    @time = device.first_seen_at.utc
    @ip = device.ip_address
    @agent = device.user_agent
    @url = Rails.application.routes.url_helpers.devices_url(**Portal.url_options)
    mail to: user.email, subject: "Sign-in from a new device"
  end
end
