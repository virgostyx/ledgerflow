require 'rails_helper'
require 'erb'
require 'yaml'

# Solid Queue in production: the queues the code uses are each served by an explicit worker, the batch work of the agent cannot starve the others,
# and no worker has more threads than its database connections allow (threads + 2, with RAILS_MAX_THREADS = 5).
RSpec.describe 'config/queue.yml' do
  let(:path) { Rails.root.join('config/queue.yml') }
  let(:production) { YAML.safe_load(ERB.new(path.read).result, aliases: true).fetch('production') }
  let(:workers) { production.fetch('workers') }
  let(:used_queues) { Dir[Rails.root.join('app/**/*.rb')].flat_map { |file| File.read(file).scan(/queue_as :(\w+)/) }.flatten.uniq }

  it 'serves every queue the code uses, by name' do
    served = workers.flat_map { |worker| Array(worker['queues']).flat_map { |queues| queues.to_s.split(',').map(&:strip) } }
    expect(served).not_to include('*')
    expect(used_queues - served).to be_empty
  end

  it 'gives the batch work of the agent a worker of its own' do
    batch = workers.select { |worker| worker['queues'].to_s.include?('agent_batch') }
    expect(batch.size).to eq(1)
    expect(batch.first['queues'].to_s.split(',').map(&:strip)).to eq([ 'agent_batch' ])
  end

  it 'keeps every worker within the connection pool' do
    workers.each { |worker| expect(worker.fetch('threads') + 2).to be <= 5 }
  end

  it 'has a dispatcher' do
    expect(production.fetch('dispatchers')).not_to be_empty
  end
end
