require 'rails_helper'

RSpec.describe Accounting::SendPaymentReminder do
  include_context 'with_open_fiscal_year'
  include ActiveJob::TestHelper

  let(:user)    { create(:user) }
  let(:partner) { create(:partner, name: 'Sodexo Belgium', email: 'accounts@sodexo.example') }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  def overdue(days: 20, total: 121, **attrs)
    create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, due_date: Date.current - days, total_incl_vat: total, **attrs)
  end

  def reminder_jobs = enqueued_jobs.map { |j| [ j['job_class'], j['arguments'] ] }.select { |name, _| name == 'Accounting::PaymentReminderJob' }

  def call(recipient: 'accounts@sodexo.example') = described_class.call(partner: partner, recipient: recipient, user: user)

  it 'records the reminder with its level, its invoices and what is due on each, and queues its delivery' do
    a = overdue(days: 40, total: 100)
    b = overdue(days: 10, total: 50)

    result = call

    expect(result).to be_success
    reminder = result[:reminder]
    expect(reminder).to be_queued.and have_attributes(partner: partner, level: 1, recipient: 'accounts@sodexo.example', sent_by: user)
    expect(reminder.items.to_h { |i| [ i.invoice, i.amount_due ] }).to eq(a => 100, b => 50)
    expect(reminder_jobs).to eq([ [ 'Accounting::PaymentReminderJob', [ reminder.id ] ] ])
  end

  it 'words the subject after the level and the entity' do
    overdue
    entity.update!(legal_name: 'Acme Consulting')
    expect(call[:reminder].subject).to eq('Payment reminder: overdue invoices from Acme Consulting')
  end

  it 'uses the second reminder subject at level 2' do
    a = overdue
    entity.update!(legal_name: 'Acme Consulting')
    create(:payment_reminder, partner: partner, level: 1, created_at: 30.days.ago, status: :sent).items.create!(invoice: a, amount_due: 121)
    expect(call[:reminder]).to have_attributes(level: 2, subject: 'Second reminder: overdue invoices from Acme Consulting')
  end

  it 'uses the formal notice subject at level 3' do
    a = overdue
    create(:payment_reminder, partner: partner, level: 2, created_at: 30.days.ago, status: :sent).items.create!(invoice: a, amount_due: 121)
    expect(call[:reminder]).to have_attributes(level: 3, subject: 'Formal notice: overdue invoices from ' + entity.legal_name)
  end

  describe 'refusals' do
    def refused(matching)
      expect { @result = call }.not_to change(Accounting::PaymentReminder, :count)
      expect(@result).to be_failure
      expect(@result.message).to match(matching)
      expect(reminder_jobs).to be_empty
    end

    it 'refuses a customer with nothing overdue' do
      create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, due_date: Date.current + 5, total_incl_vat: 100)
      refused(/nothing overdue/i)
    end

    it 'refuses a customer reminded less than 14 days ago' do
      a = overdue
      create(:payment_reminder, partner: partner, created_at: 3.days.ago, status: :sent).items.create!(invoice: a, amount_due: 121)
      refused(/already reminded/i)
    end

    it 'refuses an invalid e-mail address' do
      overdue
      expect { @result = call(recipient: 'nope') }.not_to change(Accounting::PaymentReminder, :count)
      expect(@result).to be_failure
      expect(@result.message).to match(/recipient/i)
    end

    it 'refuses a missing e-mail address' do
      overdue
      expect(call(recipient: '  ')).to be_failure
    end
  end

  it 'cannot leave a reminder without its invoices: all or nothing' do
    overdue
    allow_any_instance_of(Accounting::PaymentReminderItem).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(Accounting::PaymentReminderItem.new))
    expect { expect(call).to be_failure }.not_to change(Accounting::PaymentReminder, :count)
    expect(reminder_jobs).to be_empty
  end
end
