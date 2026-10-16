# What the clients are told: how many new publications, from which company, and a link. No title, no amount, no name of a third party (§2.5).
class Portal::NotificationMailer < ApplicationMailer
  def new_publications(user, company_name, count)
    @count = count
    @company_name = company_name
    @url = Rails.application.routes.url_helpers.publications_url(**Portal.url_options)
    mail to: user.email, subject: "#{count} new #{'publication'.pluralize(count)} from #{company_name}"
  end

  def upload_needs_attention(user, company_name)
    @company_name = company_name
    @url = Rails.application.routes.url_helpers.uploads_url(**Portal.url_options)
    mail to: user.email, subject: "Something you sent to #{company_name} needs your attention"
  end
end
