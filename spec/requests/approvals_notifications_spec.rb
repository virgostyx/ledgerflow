require "rails_helper"

# B01a: what the timers tell an approver shows in the notifications of the application, and opens the invoice.
RSpec.describe "Approval notifications", type: :request do
  include_context "with entity"

  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:approver)    { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:invoice)     { create(:invoice, :supplier, fiscal_year: fiscal_year) }
  let(:request_record) do
    policy = Approvals::Policy.create!(name: "p", subject: :purchase_invoice, priority: 1)
    policy.steps.create!(position: 1, mode: :any_of, approver_user_ids: [ approver.id ])
    Approvals::Submit.call(invoice: invoice, user: nil)[:request]
  end

  before { sign_in approver }

  %w[approval_reminder approval_escalated approval_rerouted].each do |event|
    it "says what #{event} is about, and opens the invoice" do
      notification = Accounting::Notify.call(user: approver, event: "#{event}:#{request_record.id}:1", subject: request_record)

      get accounting_notifications_path
      expect(response.body).to match(/waiting for your approval|escalated to you|sent to you because/i)
      expect(response.body).not_to include("#{event}:")

      post read_accounting_notification_path(notification)
      expect(response).to redirect_to(accounting_invoice_path(invoice))
    end
  end
end
