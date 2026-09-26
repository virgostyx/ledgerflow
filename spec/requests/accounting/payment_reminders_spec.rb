require 'rails_helper'

RSpec.describe 'Accounting::PaymentReminders', type: :request do
  include_context 'with_open_fiscal_year'
  include ActiveJob::TestHelper

  let(:accountant) { create(:user, role: :accountant) }
  let(:manager)    { create(:user, role: :manager) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:manager_membership)    { create(:user_entity, :manager, user: manager, entity: entity) }
  let(:alice) { create(:partner, name: 'Alice SA', email: 'alice@example.com') }
  let(:bob)   { create(:partner, name: 'Bob NV', email: nil) }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before { sign_in accountant }

  def overdue(partner, days: 20, total: 121)
    create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, due_date: Date.current - days, total_incl_vat: total)
  end

  describe 'GET /accounting/payment_reminders' do
    it 'lists the customers with overdue invoices, their total and the level proposed' do
      overdue(alice, days: 40, total: 100)
      overdue(alice, days: 10, total: 21)
      get accounting_payment_reminders_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Alice SA', '40 days', Accounting::MoneyPresenter.new(121).format, 'Payment reminder')
    end

    it 'offers a checkbox and the e-mail address of a customer that can be reminded' do
      overdue(alice)
      get accounting_payment_reminders_path
      page = Nokogiri::HTML(response.body)

      expect(page.at_css("input[type=checkbox][name='partner_ids[]'][value='#{alice.id}']")).to be_present
      expect(page.at_css("input[name='recipients[#{alice.id}]']")['value']).to eq('alice@example.com')
    end

    it 'lets an address be typed for a customer without one' do
      overdue(bob)
      get accounting_payment_reminders_path
      expect(Nokogiri::HTML(response.body).at_css("input[name='recipients[#{bob.id}]']")['value']).to be_blank
    end

    it 'shows when a customer was reminded and does not offer it again within 14 days' do
      a = overdue(alice)
      create(:payment_reminder, partner: alice, status: :sent, created_at: 3.days.ago).items.create!(invoice: a, amount_due: 121)
      get accounting_payment_reminders_path

      expect(response.body).to include('Reminded')
      expect(Nokogiri::HTML(response.body).at_css("input[type=checkbox][value='#{alice.id}']")).to be_nil
    end

    it 'says so when nothing is overdue' do
      get accounting_payment_reminders_path
      expect(response.body).to include('Nothing is overdue')
    end

    it 'is refused to a manager' do
      sign_in manager
      get accounting_payment_reminders_path
      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include('Alice SA')
    end
  end

  describe 'POST /accounting/payment_reminders' do
    def jobs = enqueued_jobs.select { |j| j['job_class'] == 'Accounting::PaymentReminderJob' }

    it 'queues one reminder per selected customer with the address given' do
      overdue(alice)
      overdue(bob)

      expect {
        post accounting_payment_reminders_path, params: { partner_ids: [ alice.id, bob.id ], recipients: { alice.id => 'alice@example.com', bob.id => 'bob@example.com' } }
      }.to change(Accounting::PaymentReminder, :count).by(2)

      expect(response).to redirect_to(accounting_payment_reminders_path)
      expect(flash[:notice]).to include('2')
      expect(jobs.size).to eq(2)
      expect(Accounting::PaymentReminder.find_by(partner: bob).recipient).to eq('bob@example.com')
    end

    it 'does nothing and says so when no customer is selected' do
      expect { post accounting_payment_reminders_path }.not_to change(Accounting::PaymentReminder, :count)
      expect(flash[:alert]).to be_present
    end

    it 'reports the customers it could not remind, and reminds the others' do
      overdue(alice)
      overdue(bob)

      expect {
        post accounting_payment_reminders_path, params: { partner_ids: [ alice.id, bob.id ], recipients: { alice.id => 'alice@example.com', bob.id => '' } }
      }.to change(Accounting::PaymentReminder, :count).by(1)

      expect(flash[:notice]).to include('1')
      expect(flash[:alert]).to include('Bob NV')
    end

    it 'ignores a customer that is not one of the entity partners' do
      other = ActsAsTenant.with_tenant(create(:entity)) { create(:partner) }
      expect {
        post accounting_payment_reminders_path, params: { partner_ids: [ other.id ], recipients: { other.id => 'x@example.com' } }
      }.not_to change(Accounting::PaymentReminder, :count)
    end

    it 'is refused to a manager' do
      sign_in manager
      overdue(alice)
      expect {
        post accounting_payment_reminders_path, params: { partner_ids: [ alice.id ], recipients: { alice.id => 'alice@example.com' } }
      }.not_to change(Accounting::PaymentReminder, :count)
    end
  end

  describe 'the invoice page' do
    it 'shows the reminders that covered the invoice' do
      a = overdue(alice)
      create(:payment_reminder, partner: alice, level: 2, status: :sent, recipient: 'alice@example.com').items.create!(invoice: a, amount_due: 121)
      get accounting_invoice_path(a)

      expect(response.body).to include('Payment reminders', 'alice@example.com', 'Level 2')
    end

    it 'shows no reminder section for an invoice never reminded' do
      get accounting_invoice_path(overdue(alice))
      expect(response.body).not_to include('Payment reminders')
    end
  end
end
