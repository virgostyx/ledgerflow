require 'rails_helper'

RSpec.describe Accounting::Journal, 'currency' do
  include_context 'with entity'

  it 'is EUR by default' do
    expect(build(:journal, :cash).currency).to eq('EUR')
  end

  it 'accepts a foreign currency on a cash journal' do
    expect(create(:journal, :cash, currency: 'ZMW')).to be_persisted
  end

  it 'refuses an unknown currency' do
    journal = build(:journal, :cash, currency: 'XXX', default_account: create(:account, :cash))
    journal.validate
    expect(journal.errors[:currency]).to be_present
  end

  it 'keeps a foreign currency to cash journals (a bank account holds its own)' do
    journal = build(:journal, :bank, currency: 'ZMW', default_account: create(:account, :bank))
    journal.validate
    expect(journal.errors[:currency]).to be_present
  end

  it 'cannot change once entries are recorded' do
    journal = create(:journal, :cash)
    allow(journal).to receive_message_chain(:journal_entries, :exists?).and_return(true)
    journal.currency = 'ZMW'
    expect(journal).not_to be_valid
  end
end
