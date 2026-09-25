require 'rails_helper'

RSpec.describe Peppol::SimulatorDeliveryJob do
  include ActiveJob::TestHelper

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  # The message id is only stored on the invoice when the sending transaction commits: a job that ran before would find
  # nothing and the invoice would stay queued for ever.
  it 'is not enqueued until the transaction that enqueues it has committed' do
    ApplicationRecord.transaction do
      described_class.perform_later('SIM-1', 'delivered')
      expect(enqueued_jobs).to be_empty
    end

    expect(enqueued_jobs.size).to eq(1)
  end
end
