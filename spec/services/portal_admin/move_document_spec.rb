require 'rails_helper'

# B02b (Sécurité): a document that came to the wrong company can be moved by the team, only by someone who works in both, only while it is untouched, and with a trace in the audit trail of both.
RSpec.describe PortalAdmin::MoveDocument do
  include DocumentFiles

  let(:from)  { create(:entity) }
  let(:to)    { create(:entity) }
  let(:staff) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: from); create(:user_entity, :accountant, user: u, entity: to) } }
  let(:document) { ActsAsTenant.with_tenant(from) { Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('wrong company')), filename: 'a.pdf', user: nil, origin: :portal)[:document] } }

  def audit(entity, action) = ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.where(action: action).count }

  it 'puts the document in the other company, with its file, and leaves a trace in both chains' do
    result = described_class.call(document: document, to: to, by: staff)

    expect(result).to be_success
    expect(document.reload.entity_id).to eq(to.id)
    expect(ActsAsTenant.with_tenant(to) { Accounting::Document.find(document.id).file.download }).to start_with('%PDF')
    expect(ActsAsTenant.with_tenant(from) { Accounting::Document.where(id: document.id).count }).to eq(0)
    expect([ audit(from, 'document_moved_out'), audit(to, 'document_moved_in') ]).to eq([ 1, 1 ])
  end

  it 'refuses someone who does not work in the other company' do
    alone = create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: from) }
    expect(described_class.call(document: document, to: to, by: alone)).to be_failure
    expect(document.reload.entity_id).to eq(from.id)
  end

  it 'refuses a document that is already used: linked, with a task, or cut from another' do
    ActsAsTenant.with_tenant(from) { Accounting::LinkDocument.call(document: document, target: create(:journal_entry), user: staff) }
    expect(described_class.call(document: document, to: to, by: staff)).to be_failure

    other = ActsAsTenant.with_tenant(from) { Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('with task')), filename: 'b.pdf', user: nil)[:document] }
    ActsAsTenant.with_tenant(from) { Accounting::Task.create!(title: 'Look', target: other, author: staff, entity: from) }
    expect(described_class.call(document: other, to: to, by: staff)).to be_failure
  end

  it 'refuses a file the other company already has' do
    ActsAsTenant.with_tenant(to) { Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('wrong company')), filename: 'same.pdf', user: nil) }
    expect(described_class.call(document: document, to: to, by: staff)).to be_failure
  end

  it 'refuses to move to the same company, or under a legal hold' do
    expect(described_class.call(document: document, to: from, by: staff)).to be_failure
    document.update_columns(legal_hold: true, legal_hold_reason: 'dispute')
    expect(described_class.call(document: document, to: to, by: staff)).to be_failure
  end
end
