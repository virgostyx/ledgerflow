require 'rails_helper'

RSpec.describe Accounting::PeppolEvent, type: :model do
  include_context 'with entity'

  it { should belong_to(:invoice).class_name('Accounting::Invoice') }
  it { should define_enum_for(:kind).with_values(sent: 0, delivered: 1, failed: 2) }

  it 'is stamped with the time it happened' do
    expect(create(:peppol_event).occurred_at).to be_within(1.minute).of(Time.current)
  end

  it 'is listed newest first on the invoice' do
    invoice = create(:invoice, :posted)
    old    = create(:peppol_event, invoice: invoice, occurred_at: 2.hours.ago)
    recent = create(:peppol_event, invoice: invoice, occurred_at: 1.hour.ago)

    expect(invoice.peppol_events).to eq([ recent, old ])
  end

  it 'is limited to the current entity' do
    mine  = create(:peppol_event)
    other = ActsAsTenant.with_tenant(create(:entity)) { create(:peppol_event) }

    expect(described_class.all).to include(mine)
    expect(described_class.all).not_to include(other)
  end
end
