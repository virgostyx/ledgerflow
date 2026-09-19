require 'rails_helper'

RSpec.describe Seeders::UsersSeeder do
  def seed
    expect { described_class.call }.to output(/\[Users\]/).to_stdout
  end

  it 'creates the demo users with a working password and their role' do
    expect { seed }.to change(User, :count).by(described_class::USERS.size)

    admin = User.find_by!(email: 'admin@ledgerflow.test')
    expect(admin).to be_admin
    expect(admin.valid_password?('password123!')).to be true
  end

  it 'is idempotent' do
    seed
    expect { seed }.not_to change(User, :count)
  end
end
