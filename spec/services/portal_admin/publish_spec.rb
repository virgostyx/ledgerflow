require 'rails_helper'

# B02a: "the portal publishes, it does not expose". A publication is frozen: its files and their SHA-256, its title. Correcting is publishing a new version; withdrawing hides it.
RSpec.describe PortalAdmin::Publish do
  include_context 'with entity'

  let(:staff) { create(:user) }
  let(:pdf)   { { filename: 'balance.pdf', content_type: 'application/pdf', data: "%PDF-1.4\nbalance sheet\n%%EOF" } }

  def publish(**args)
    described_class.call(entity: entity, kind: 'monthly_report', title: 'March 2026', files: [ pdf ], by: staff, **args)
  end

  it 'freezes the files with their SHA-256' do
    publication = publish[:publication]

    file = publication.files.sole
    expect(file.sha256).to eq(Digest::SHA256.hexdigest(pdf[:data]))
    expect(file).to have_attributes(filename: 'balance.pdf', byte_size: pdf[:data].bytesize, content_type: 'application/pdf')
    expect(publication).to have_attributes(version: 1, status: 'published', published_by_id: staff.id)
    expect(publication.token.length).to be >= 22
  end

  it 'is in the audit trail, without the content' do
    publish
    log = Accounting::AuditLog.where(entity_id: entity.id, action: 'portal_published').sole
    expect(log.payload.to_json).not_to include('balance sheet')
    expect(log.payload['files'].first['sha256']).to eq(Digest::SHA256.hexdigest(pdf[:data]))
  end

  it 'refuses a publication without a file, without a title, of an unknown kind, or too large' do
    expect(publish(files: [])).to be_failure
    expect(publish(title: '')).to be_failure
    expect(publish(kind: 'secret')).to be_failure
    expect(publish(files: [ pdf.merge(data: 'x' * (PortalAdmin::Publish::MAX_FILE_BYTES + 1)) ])).to be_failure
  end

  it 'refuses a type of file the portal does not serve' do
    expect(publish(files: [ pdf.merge(filename: 'run.exe', content_type: 'application/x-msdownload') ])).to be_failure
  end

  it 'cannot be changed afterwards, whatever is tried' do
    publication = publish[:publication]
    expect { publication.update_columns(title: 'Other') }.to raise_error(ActiveRecord::StatementInvalid)
    expect { publication.files.first.update_columns(sha256: 'x') }.to raise_error(ActiveRecord::StatementInvalid)
    expect { publication.files.first.delete }.to raise_error(ActiveRecord::StatementInvalid)
    expect { publication.delete }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'a new version replaces the previous one, which is kept and marked replaced' do
    first = publish[:publication]
    second = publish(title: 'March 2026 (corrected)', replaces: first)[:publication]

    expect(second).to have_attributes(version: 2, replaces_id: first.id)
    expect(first.reload.replaced_by_id).to eq(second.id)
    expect(Portal::Publication.visible).to contain_exactly(second)
    expect(Accounting::AuditLog.where(entity_id: entity.id, action: 'portal_published').count).to eq(2)
  end

  it 'refuses to replace a publication twice, or one of another company' do
    first = publish[:publication]
    publish(replaces: first)
    expect(publish(replaces: first)).to be_failure
    foreign = described_class.call(entity: create(:entity), kind: 'other', title: 'x', files: [ pdf ], by: staff)[:publication]
    expect(publish(replaces: foreign)).to be_failure
  end

  it 'withdrawing hides it and keeps it, with the reason' do
    publication = publish[:publication]
    PortalAdmin::Withdraw.call(publication: publication, reason: 'sent by mistake', by: staff)

    publication.reload
    expect(publication).to be_withdrawn
    expect(publication.withdrawal_reason).to eq('sent by mistake')
    expect(publication.files.count).to eq(1)
    expect(Portal::Publication.visible).to be_empty
    expect(Accounting::AuditLog.where(entity_id: entity.id, action: 'portal_withdrawn')).to exist
  end

  it 'is visible only until it expires' do
    publication = publish(expires_at: 2.days.from_now)[:publication]
    expect(Portal::Publication.visible).to contain_exactly(publication)
    travel_to(3.days.from_now) { expect(Portal::Publication.visible).to be_empty }
  end

  it 'names its recipients, or goes to everyone who may see publications' do
    reader = create(:portal_user)
    publication = publish(recipients: [ reader ])[:publication]
    expect(publication.recipients).to contain_exactly(reader)
  end

  it 'takes its files from documents of the company, checking their SHA-256' do
    document = create(:document)
    result = described_class.call(entity: entity, kind: 'other', title: 'From a document', documents: [ document ], by: staff)

    expect(result[:publication].files.sole.sha256).to eq(document.sha256)
  end

  it 'refuses when the portal is off' do
    entity.update!(features: { 'b02a' => false })
    expect(publish).to be_failure
  end
end
