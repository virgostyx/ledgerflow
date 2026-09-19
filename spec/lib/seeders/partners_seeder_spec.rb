require 'rails_helper'

RSpec.describe Seeders::PartnersSeeder do
  include_context 'with entity'

  def seed
    expect { described_class.call }.to output(/\[Partners\]/).to_stdout
  end

  it 'creates every demo supplier (all seed data passes the model validations)' do
    expect { seed }.to change(Accounting::Partner, :count).by(described_class::SUPPLIERS.size)
    expect(Accounting::Partner.pluck(:partner_type).uniq).to eq([ 'supplier' ])
  end

  it 'is idempotent' do
    seed
    expect { seed }.not_to change(Accounting::Partner, :count)
  end
end
