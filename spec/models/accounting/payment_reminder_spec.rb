require 'rails_helper'

RSpec.describe Accounting::PaymentReminder, type: :model do
  include_context 'with_open_fiscal_year'

  describe 'validations' do
    subject { build(:payment_reminder) }

    it { is_expected.to be_valid }
    it { should validate_presence_of(:recipient) }
    it { should validate_presence_of(:subject) }
    it { should validate_inclusion_of(:level).in_array([ 1, 2, 3 ]) }

    it 'refuses a recipient that is not an e-mail address' do
      expect(build(:payment_reminder, recipient: 'not-an-email')).not_to be_valid
    end
  end

  describe 'associations' do
    it { should belong_to(:partner).class_name('Accounting::Partner') }
    it { should belong_to(:sent_by).class_name('User') }
    it { should have_many(:items).class_name('Accounting::PaymentReminderItem').dependent(:destroy) }
    it { should have_many(:invoices).through(:items) }
  end

  it { should define_enum_for(:status).with_values(queued: 0, sent: 1, failed: 2) }

  describe 'items' do
    it 'record the amount still due on each invoice when the reminder was made' do
      reminder = create(:payment_reminder)
      invoice  = create(:invoice, :posted, partner: reminder.partner, fiscal_year: fiscal_year)
      item     = reminder.items.create!(invoice: invoice, amount_due: 121.5)

      expect(reminder.invoices).to contain_exactly(invoice)
      expect(item.amount_due).to eq(121.5)
    end

    it 'need an amount due' do
      expect(build(:payment_reminder).items.build(amount_due: nil)).not_to be_valid
    end
  end

  it 'lists a reminder on the invoices it covers, newest first' do
    partner = create(:partner)
    invoice = create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year)
    old = create(:payment_reminder, partner: partner, created_at: 20.days.ago).tap { |r| r.items.create!(invoice: invoice, amount_due: 10) }
    new = create(:payment_reminder, partner: partner, level: 2).tap { |r| r.items.create!(invoice: invoice, amount_due: 10) }

    expect(invoice.payment_reminders).to eq([ new, old ])
  end
end
