# F13c: where the entity is told of what happens (outgoing webhooks). The owner's: a subscription sends the entity's events outside. The secret is shown once,
# when the subscription is made and when it is rotated; what is done here is written in the audit trail, never the secret.
class Accounting::Settings::WebhookSubscriptionsController < Accounting::Settings::BaseController
  before_action { require_feature!(:f13) }
  before_action :set_subscription, only: %i[edit update destroy deliveries rotate_secret resume replay]

  def index
    @subscriptions = WebhookSubscription.order(:name)
  end

  def new
    @subscription = WebhookSubscription.new(events: WebhookSubscription::EVENTS)
  end

  def create
    @subscription = WebhookSubscription.new(subscription_params.merge(secret: WebhookSubscription.generate_secret, created_by: current_user))
    if @subscription.save
      audit("webhook_subscription_created", @subscription)
      @secret = @subscription.secret
      render :secret
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @subscription.update(subscription_params)
      audit("webhook_subscription_updated", @subscription)
      redirect_to accounting_settings_webhook_subscriptions_path, notice: "Webhook saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    audit("webhook_subscription_deleted", @subscription)
    @subscription.destroy!
    redirect_to accounting_settings_webhook_subscriptions_path, notice: "Webhook deleted."
  end

  def rotate_secret
    @secret = @subscription.rotate_secret!
    audit("webhook_secret_rotated", @subscription)
    render :secret
  end

  def resume
    @subscription.resume!
    audit("webhook_subscription_resumed", @subscription)
    redirect_to deliveries_accounting_settings_webhook_subscription_path(@subscription), notice: "Resumed. What was held can be sent again from the log."
  end

  def deliveries
    @deliveries = @subscription.deliveries.order(id: :desc).limit(100)
  end

  def replay
    delivery = @subscription.deliveries.find(params[:delivery_id])
    Webhooks::Replay.call(delivery)
    audit("webhook_delivery_replayed", @subscription, delivery_id: delivery.id)
    redirect_to deliveries_accounting_settings_webhook_subscription_path(@subscription), notice: "Sent again."
  end

  private

  def authorize_settings_access!
    return if Accounting::Settings::BasePolicy.new(current_user, :settings).destroy?

    flash[:alert] = t("errors.not_authorized")
    redirect_to accounting_root_path
  end

  def set_subscription = @subscription = WebhookSubscription.find(params[:id])

  def subscription_params
    params.require(:webhook_subscription).permit(:name, :url, :max_failures, events: []).tap { |p| p[:events] = Array(p[:events]).compact_blank }
  end

  def audit(action, subscription, **extra)
    Accounting::AuditLog.record!(auditable: subscription, action: action, user: current_user,
                                 payload: { name: subscription.name, url: subscription.url, events: subscription.events }.merge(extra))
  end
end
