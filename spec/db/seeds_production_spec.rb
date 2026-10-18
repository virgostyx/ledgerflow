require 'rails_helper'

# db:prepare replays the seeds when it creates a database: the first start of the container in production created the demo accounts
# (admin@ledgerflow.test and four others, one password known to the repository) and the demo company. Production must never get them.
RSpec.describe 'db/seeds.rb in production' do
  around do |example|
    saved = ENV['ALLOW_DEMO_SEEDS']
    ENV.delete('ALLOW_DEMO_SEEDS')
    example.run
  ensure
    ENV['ALLOW_DEMO_SEEDS'] = saved
  end

  def load_seeds_as(environment)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(environment))
    allow(Seeders::UsersSeeder).to receive(:call)
    allow(Seeders::VatCodesSeeder).to receive(:call)
    allow(Seeders::CurrenciesSeeder).to receive(:call)
    capture_stdout { load Rails.root.join('db/seeds.rb').to_s }
  end

  def capture_stdout
    previous = $stdout
    $stdout = StringIO.new
    yield
  rescue ActiveRecord::RecordNotFound
    nil # the demo administrator does not exist in this test: only the guard matters
  ensure
    $stdout = previous
  end

  it 'creates no account in production' do
    load_seeds_as('production')
    expect(Seeders::UsersSeeder).not_to have_received(:call)
  end

  it 'creates the demo accounts in development and test' do
    load_seeds_as('development')
    expect(Seeders::UsersSeeder).to have_received(:call)
  end
end
