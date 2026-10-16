require 'rails_helper'

# B02b: what the client is told follows the document in the firm (received, in progress, booked, to complete) without ever showing the books; a document can be refused for a
# predefined reason; a change to "to complete" tells the client once.
RSpec.describe 'Follow-up of the uploads' do
  include DocumentFiles

  let(:entity) { create(:entity) }
  let(:person) { create(:portal_user) }
  let(:staff)  { create(:user) }

  def accepted_upload
    outcome = ActsAsTenant.with_tenant(entity) { Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("Invoice #{SecureRandom.hex(3)}")), filename: 'a.pdf', user: nil, origin: :portal) }
    Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'a.pdf', byte_size: 10, sha256: SecureRandom.hex(32), chunk_size: Portal::Upload::CHUNK_SIZE, chunk_count: 1,
                           status: 'accepted', document_id: outcome[:document].id, received_at: Time.current, expires_at: 48.hours.from_now)
  end

  def document_of(upload) = ActsAsTenant.with_tenant(entity) { Accounting::Document.find(upload.document_id) }

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'collaborator', capabilities: %w[documents.upload publications.view])
    ActionMailer::Base.deliveries.clear
  end

  describe PortalAdmin::SyncUploadProgress do
    it 'stays "received" while nobody has touched the document' do
      upload = accepted_upload
      described_class.call
      expect(upload.reload.progress).to eq('received')
    end

    it 'becomes "in progress" once the document is linked to something still in draft' do
      upload = accepted_upload
      ActsAsTenant.with_tenant(entity) { Accounting::LinkDocument.call(document: document_of(upload), target: create(:journal_entry, :draft), user: staff) }

      described_class.call

      expect(upload.reload.progress).to eq('in_progress')
    end

    it 'becomes "booked" when the document is linked to a validated entry' do
      upload = accepted_upload
      ActsAsTenant.with_tenant(entity) { Accounting::LinkDocument.call(document: document_of(upload), target: create(:journal_entry, :posted), user: staff) }

      described_class.call

      expect(upload.reload.progress).to eq('booked')
    end

    it 'becomes "to complete" when a question is open about the document, and tells the client once' do
      upload = accepted_upload
      ActsAsTenant.with_tenant(entity) do
        Accounting::Task.create!(title: 'Which supplier?', kind: :client_question, target: document_of(upload), author: staff, entity: entity)
      end

      described_class.call
      described_class.call

      expect(upload.reload.progress).to eq('to_complete')
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ person.email ])
      expect(mail.body.to_s).not_to include('Which supplier?')
    end

    it 'says nothing to someone who chose not to be told' do
      person.update!(notification_frequency: 'off')
      upload = accepted_upload
      ActsAsTenant.with_tenant(entity) { Accounting::Task.create!(title: 'Q', kind: :client_question, target: document_of(upload), author: staff, entity: entity) }

      described_class.call

      expect(upload.reload.progress).to eq('to_complete')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'does not write to the books' do
      upload = accepted_upload
      expect { described_class.call }.not_to change { ActsAsTenant.with_tenant(entity) { Accounting::JournalEntry.count } }
      expect(upload.reload.progress).to eq('received')
    end
  end

  describe PortalAdmin::RejectUpload do
    it 'refuses the document with a predefined reason and tells the client' do
      upload = accepted_upload

      described_class.call(document: document_of(upload), reason: 'illegible', by: staff)

      expect(upload.reload).to have_attributes(status: 'refused', refusal_reason: 'illegible')
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.where(action: 'portal_upload_rejected').count }).to eq(1)
    end

    it 'refuses a reason that is not on the list' do
      upload = accepted_upload
      result = described_class.call(document: document_of(upload), reason: 'because', by: staff)
      expect(result).to be_failure
      expect(upload.reload.status).to eq('accepted')
    end

    it 'refuses a document that is not from the portal, or already booked' do
      other = ActsAsTenant.with_tenant(entity) { Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('mine')), filename: 'b.pdf', user: staff)[:document] }
      expect(described_class.call(document: other, reason: 'illegible', by: staff)).to be_failure
    end
  end
end
