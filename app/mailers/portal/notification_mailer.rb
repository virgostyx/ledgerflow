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

  def documents_requested(user, company_name, count)
    @company_name = company_name
    @count = count
    @url = Rails.application.routes.url_helpers.document_requests_url(**Portal.url_options)
    mail to: user.email, subject: "#{company_name} asks you for #{count} #{'document'.pluralize(count)}"
  end

  def questions_waiting(user, company_name, count)
    @company_name = company_name
    @count = count
    @url = Rails.application.routes.url_helpers.questions_url(**Portal.url_options)
    mail to: user.email, subject: "#{company_name} has #{count} #{'question'.pluralize(count)} for you"
  end

  def new_message(user, company_name)
    @company_name = company_name
    @url = Rails.application.routes.url_helpers.messages_url(**Portal.url_options)
    mail to: user.email, subject: "#{company_name} wrote to you"
  end

  def dashboard_alert(user, company_name)
    @company_name = company_name
    @url = Rails.application.routes.url_helpers.portal_dashboard_url(**Portal.url_options)
    mail to: user.email, subject: "#{company_name}: something to look at on your dashboard"
  end
end
