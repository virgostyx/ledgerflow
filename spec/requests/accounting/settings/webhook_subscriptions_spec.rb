require "rails_helper"

RSpec.describe "Accounting::Settings::WebhookSubscriptions", type: :request do
  include_context "with_open_fiscal_year"

  let(:admin)      { create(:user, role: :admin) }
  let(:accountant) { create(:user, role: :accountant) }
  let(:url)        { "https://hooks.example.com/ledgerflow" }

  before do
    create(:user_entity, :admin, user: admin, entity: entity)
    create(:user_entity, :accountant, user: accountant, entity: entity)
    sign_in admin
  end

  def params(**attrs) = { webhook_subscription: { name: "ERP", url: url, events: [ "", "entry.posted", "period.locked" ], max_failures: "5" }.merge(attrs) }

  it "creates a subscription, shows its secret once, and records it in the audit trail without the secret" do
    expect { post accounting_settings_webhook_subscriptions_path, params: params }.to change(WebhookSubscription, :count).by(1)
    subscription = WebhookSubscription.last
    expect(response.body).to include(subscription.secret, "will not be shown again")
    expect(subscription).to have_attributes(events: %w[entry.posted period.locked], max_failures: 5, created_by: admin)

    get accounting_settings_webhook_subscriptions_path
    expect(response.body).to include("ERP", url).and not_include(subscription.secret)
    log = Accounting::AuditLog.where(action: "webhook_subscription_created").last
    expect(log.payload.to_json).not_to include(subscription.secret)
    expect(log.payload).to include("name" => "ERP", "url" => url)
  end

  it "refuses an address that is not public, an unknown event, and no event" do
    post accounting_settings_webhook_subscriptions_path, params: params(url: "http://hooks.example.com")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be an https URL")
    post accounting_settings_webhook_subscriptions_path, params: params(events: [ "" ])
    expect(response.body).to include("choose at least one")
    expect(WebhookSubscription.count).to eq(0)
  end

  it "edits, rotates the secret (shown once, the old one signing on for a day), resumes, and deletes" do
    subscription = WebhookSubscription.create!(name: "ERP", url: url, events: %w[period.locked], secret: WebhookSubscription.generate_secret)
    old = subscription.secret

    patch accounting_settings_webhook_subscription_path(subscription), params: params(name: "ERP 2")
    expect(subscription.reload.name).to eq("ERP 2")

    post rotate_secret_accounting_settings_webhook_subscription_path(subscription)
    expect(response.body).to include(subscription.reload.secret)
    expect(subscription.signing_secrets).to eq([ subscription.secret, old ])
    expect(Accounting::AuditLog.where(action: "webhook_secret_rotated")).to exist

    subscription.suspend!("too many failures")
    get deliveries_accounting_settings_webhook_subscription_path(subscription)
    expect(response.body).to include("Suspended", "too many failures", "Resume")
    post resume_accounting_settings_webhook_subscription_path(subscription)
    expect(subscription.reload).not_to be_suspended

    expect { delete accounting_settings_webhook_subscription_path(subscription) }.to change(WebhookSubscription, :count).by(-1)
  end

  it "shows the log of deliveries and sends one again" do
    subscription = WebhookSubscription.create!(name: "ERP", url: url, events: %w[period.locked], secret: WebhookSubscription.generate_secret)
    delivery = WebhookDelivery.create!(webhook_subscription: subscription, event: "period.locked", event_id: "e1", payload: { "id" => "e1" }, status: "failed", attempts: 8, last_response_code: 503)

    get deliveries_accounting_settings_webhook_subscription_path(subscription)
    expect(response.body).to include("period.locked", "Failed", "503", "Send again")

    expect { post replay_delivery_accounting_settings_webhook_subscription_path(subscription, delivery_id: delivery.id) }
      .to change(WebhookDelivery, :count).by(1).and have_enqueued_job(Webhooks::DeliverJob)
    expect(WebhookDelivery.last).to have_attributes(replay_of: delivery, event_id: "e1")
  end

  it "belongs to the owner and to the entities that turned the feature on" do
    subscription = WebhookSubscription.create!(name: "ERP", url: url, events: %w[period.locked], secret: WebhookSubscription.generate_secret)
    sign_in accountant
    get accounting_settings_webhook_subscriptions_path
    expect(response).to redirect_to(accounting_root_path)
    expect { post accounting_settings_webhook_subscriptions_path, params: params }.not_to change(WebhookSubscription, :count)

    sign_in admin
    entity.update!(features: { "f13" => false })
    get accounting_settings_webhook_subscriptions_path
    expect(response).to redirect_to(accounting_root_path)
    expect(subscription).to be_persisted
  end

  it "does not show the subscriptions of another entity" do
    other = create(:entity)
    foreign = ActsAsTenant.with_tenant(other) { WebhookSubscription.create!(name: "Theirs", url: url, events: %w[period.locked], secret: "s", entity: other) }
    get accounting_settings_webhook_subscriptions_path
    expect(response.body).not_to include("Theirs")
    get edit_accounting_settings_webhook_subscription_path(foreign)
    expect(response).to have_http_status(:not_found)
  end
end
