# F08: the public page where a third party answers the question of a task through its signed link. It shows the question and the name of the
# entity, nothing else of the task or of the books; the answer is a comment with no author and files for the document inbox.
class ExternalRepliesController < ApplicationController
  skip_before_action :authenticate_user!
  layout "devise"

  around_action :in_the_tenant_of_the_task
  before_action :keep_the_link_private

  def show; end

  def create
    result = Accounting::ReceiveExternalReply.call(task: @task, name: params[:name], body: params[:body], files: Array(params[:files]).select { |f| f.respond_to?(:tempfile) }, ip: request.remote_ip)
    if result.success?
      @refused = result[:refused]
      render :thanks
    else
      flash.now[:alert] = result.message
      render :show, status: :unprocessable_content
    end
  end

  private

  # The link is in the address: it must not leave in a Referer (the page loads external fonts) nor be indexed.
  def keep_the_link_private
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  # A link that is not valid, or has expired, or was revoked looks the same: nothing is told of why.
  def in_the_tenant_of_the_task
    @task = Accounting::Task.find_by_external_token(params[:token])
    return render(:gone, status: :not_found) unless @task && @task.entity.feature?(:f08)

    ActsAsTenant.with_tenant(@task.entity) { yield }
  end
end
