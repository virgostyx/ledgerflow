# The contract every Access Point adapter must honour, so that the rest of the application never has to know which
# provider an entity uses. The including spec defines:
#   access_point       - the adapter, built for an entity
#   send_args          - keyword arguments of a send the AP accepts (after accept_send! has stubbed it)
#   accept_send!       - makes the AP accept a send
#   refused_send_args  - keyword arguments of a send the AP refuses (stubbing what it needs)
#   delivered_webhook  - { headers:, body: } of a genuine delivery confirmation for message "MSG-1"
#   forged_webhook     - { headers:, body: } whose signature is wrong
RSpec.shared_examples 'a Peppol access point' do
  it 'declares the credentials it needs' do
    fields = access_point.class.credential_fields

    expect(fields).to be_an(Array)
    expect(fields).to all(include(:key, :label))
  end

  it 'sends a document and returns the message id given by the Access Point' do
    accept_send!
    message_id = access_point.send_document(**send_args)

    expect(message_id).to be_a(String).and(be_present)
  end

  it 'raises Peppol::AccessPoint::Error when the Access Point refuses the document' do
    args = refused_send_args
    expect { access_point.send_document(**args) }.to raise_error(Peppol::AccessPoint::Error)
  end

  it 'answers registered? with true, false or nil (unknown)' do
    expect([ true, false, nil ]).to include(access_point.registered?('0208:0123456789'))
  end

  it 'turns a genuine webhook into normalized events' do
    events = access_point.parse_webhook(**delivered_webhook)

    expect(events).to all(be_a(Peppol::Event))
    expect(events.first).to have_attributes(kind: :delivered, message_id: 'MSG-1')
  end

  it 'refuses a forged webhook' do
    expect { access_point.parse_webhook(**forged_webhook) }.to raise_error(Peppol::AccessPoint::InvalidSignature)
  end
end
