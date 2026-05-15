RSpec.shared_examples 'an immutable posted record' do
  it 'cannot be updated after posting' do
    subject.updated_at = Time.current
    expect { subject.save! }
      .to raise_error(Accounting::ImmutableRecordError)
  end

  it 'cannot be destroyed after posting' do
    expect { subject.destroy! }
      .to raise_error(Accounting::ImmutableRecordError)
  end
end
