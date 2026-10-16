# B02b: the automatic reply to the mail that brought documents: how many, and nothing of what they are.
class DocumentsMailer < ApplicationMailer
  def received(to, count, message_id)
    @count = count
    headers["Auto-Submitted"] = "auto-replied"
    headers["In-Reply-To"] = message_id if message_id.present?
    mail to: to, subject: "Received: #{count} #{'document'.pluralize(count)}"
  end
end
