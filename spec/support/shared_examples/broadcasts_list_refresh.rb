# Expects `record` (persisted) and `stream` (array of streamables) in the including context.
RSpec.shared_examples 'broadcasts list refresh' do
  it 'broadcasts a refresh to the entity stream' do
    record
    name = Turbo::StreamsChannel.send(:stream_name_from, stream)
    expect { perform_enqueued_jobs { record.touch } }
      .to have_broadcasted_to(name).with(a_string_including('action="refresh"'))
  end
end
