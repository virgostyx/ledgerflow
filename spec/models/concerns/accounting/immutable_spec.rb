require 'rails_helper'

RSpec.describe Accounting::Immutable, type: :model do
  let(:entry) { create(:journal_entry, :posted) }

  it_behaves_like 'an immutable posted record' do
    subject { entry }
  end
end
