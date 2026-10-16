require 'rails_helper'

# B02c: the integrity certificate (B03c) attached to a publication is checked again by the firm's side, and what it found is what the client is told: valid, revoked or not valid, with the date.
RSpec.describe PortalAdmin::CheckPublicationCertificates do
  include_context 'with entity'

  let(:staff) { create(:user) }
  let(:certificate) do
    IntegrityCertificate.create!(entity: entity, uuid: SecureRandom.uuid, issued_by: staff, covered_at: Time.current, through_seq: 1, anchor_number: 1, disclosure_level: 'standard',
                                 payload: { 'id' => 'x' }, body: '{"id":"x"}', key_id: 'k', signature: 'sig')
  end

  def publish(json) = PortalAdmin::Publish.call(entity: entity, kind: 'situation', title: 'With certificate', by: staff, files: [ { filename: 'certificate.json', content_type: 'application/json', data: json } ])[:publication]

  def body_of(cert) = %({"type":"ledgerflow-integrity-certificate","id":"#{cert.uuid}"})

  def result(state) = Integrity::VerifyCertificate::Result.new(state: state)

  it 'records "valid" for a certificate that checks out, with the time' do
    publication = publish(body_of(certificate))
    allow(Integrity::VerifyCertificate).to receive(:call).and_return(result(:valid))

    described_class.call

    check = Portal::CertificateCheck.sole
    expect(check).to have_attributes(publication_id: publication.id, state: 'valid')
    expect(check.checked_at).to be_within(1.minute).of(Time.current)
  end

  it 'says it again when the certificate was revoked since, or no longer checks out' do
    publication = publish(body_of(certificate))
    allow(Integrity::VerifyCertificate).to receive(:call).and_return(result(:valid))
    described_class.call
    allow(Integrity::VerifyCertificate).to receive(:call).and_return(result(:revoked))
    described_class.call
    expect(Portal::CertificateCheck.find_by(publication_id: publication.id).state).to eq('revoked')

    allow(Integrity::VerifyCertificate).to receive(:call).and_return(result(:chain_changed))
    described_class.call
    expect(Portal::CertificateCheck.sole.state).to eq('not_valid')
  end

  it 'says "unknown" when the file names a certificate this company never issued' do
    publish(%({"type":"ledgerflow-integrity-certificate","id":"#{SecureRandom.uuid}"}))
    described_class.call
    expect(Portal::CertificateCheck.sole.state).to eq('unknown')
  end

  it 'ignores a publication that has no certificate, and files that are only JSON' do
    publish('{"hello":"world"}')
    described_class.call
    expect(Portal::CertificateCheck.count).to eq(0)
  end

  it 'does not look at a withdrawn publication' do
    publication = publish(body_of(certificate))
    PortalAdmin::Withdraw.call(publication: publication, by: staff, reason: 'x')
    described_class.call
    expect(Portal::CertificateCheck.count).to eq(0)
  end
end
