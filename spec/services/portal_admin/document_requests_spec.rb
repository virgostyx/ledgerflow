require 'rails_helper'

# B02b, "Pièces demandées": the firm picks bank lines without a supporting document and asks the client for them. The client sees a date, a cleaned label and an amount, never an IBAN.
# An answer without a document opens a task for the accountant and books nothing.
RSpec.describe 'Document requests' do
  include_context 'with entity'
  include DocumentFiles

  let(:staff)  { create(:user) }
  let(:person) { create(:portal_user) }
  let(:iban)   { 'BE68539007547034' }
  let!(:line)  do
    create(:bank_transaction, amount: BigDecimal('-123.45'), counterparty_name: 'ACME Supplies', counterparty_iban: iban, description: "PAYMENT TO #{iban} INVOICE 202600123456 THANKS", transaction_date: Date.new(2026, 3, 4))
  end

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: 'director', capabilities: %w[documents.upload bank_lines.view questions.answer])
    ActionMailer::Base.deliveries.clear
  end

  describe PortalAdmin::RequestDocuments do
    it 'copies what the client may see of each line, and nothing of the bank' do
      result = described_class.call(entity: entity, lines: [ line ], message: 'Please send the invoices', due_on: Date.new(2026, 4, 15), by: staff)

      expect(result).to be_success
      copy = Portal::DocumentRequestLine.sole
      expect(copy).to have_attributes(bank_transaction_id: line.id, line_date: Date.new(2026, 3, 4), amount: BigDecimal('-123.45'), currency: 'EUR', state: 'open', label: 'ACME Supplies')
      expect(copy.attributes.values.join(' ')).not_to include(iban)
      expect(Portal::DocumentRequest.sole).to have_attributes(message: 'Please send the invoices', due_on: Date.new(2026, 4, 15), requested_by_id: staff.id)
    end

    it 'cleans the description when the line has no counterparty name: no IBAN, no long number' do
      line.update!(counterparty_name: nil)

      described_class.call(entity: entity, lines: [ line ], by: staff)

      label = Portal::DocumentRequestLine.sole.label
      expect(label).to eq('PAYMENT TO INVOICE THANKS')
    end

    it 'audits the request and tells the clients that something is asked, without saying what' do
      described_class.call(entity: entity, lines: [ line ], message: 'secret message', by: staff)

      expect(Accounting::AuditLog.where(action: 'portal_documents_requested').count).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ person.email ])
      expect(mail.body.to_s).not_to include('ACME', 'secret message', '123')
    end

    it 'does not tell someone who may not see bank lines' do
      person.grants.update_all(capabilities: %w[documents.upload])

      described_class.call(entity: entity, lines: [ line ], by: staff)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'refuses a line that already has a document, one that is not pending, and a line asked for already' do
      document = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('has one')), filename: 'a.pdf', user: staff)[:document]
      Accounting::DocumentLink.create!(document: document, target: line, created_by: staff)
      with_document = line
      done = create(:bank_transaction, status: :reconciled)
      open_one = create(:bank_transaction)
      described_class.call(entity: entity, lines: [ open_one ], by: staff)

      result = described_class.call(entity: entity, lines: [ with_document, done, open_one ], by: staff)

      expect(result).to be_failure
      expect(Portal::DocumentRequestLine.count).to eq(1)
    end

    it 'refuses to ask when the company turned the feature off, or hides the bank lines' do
      entity.update!(features: { 'b02b' => false })
      expect(described_class.call(entity: entity, lines: [ line ], by: staff)).to be_failure
      entity.update!(features: { 'b02b' => true }, portal_show_bank_lines: false)
      expect(described_class.call(entity: entity, lines: [ line ], by: staff)).to be_failure
    end

    it 'refuses to ask when nobody can see bank lines' do
      person.grants.destroy_all
      expect(described_class.call(entity: entity, lines: [ line ], by: staff)).to be_failure
    end
  end

  describe PortalAdmin::SyncDocumentRequests do
    before { PortalAdmin::RequestDocuments.call(entity: entity, lines: [ line ], by: staff) }

    let(:copy) { Portal::DocumentRequestLine.sole }

    it 'withdraws a request for a line the firm justified itself, with a message' do
      document = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('by the firm')), filename: 'a.pdf', user: staff)[:document]
      Accounting::DocumentLink.create!(document: document, target: line, created_by: staff)

      described_class.call

      expect(copy.reload).to have_attributes(state: 'withdrawn')
      expect(copy.withdrawn_reason).to match(/justified/)
    end

    it 'marks as provided a line whose document came from the client' do
      document = Accounting::UploadDocument.call(io: StringIO.new(sample_pdf('from the client')), filename: 'a.pdf', user: nil, origin: :portal)[:document]
      upload = Portal::Upload.create!(entity_id: entity.id, portal_user: person, filename: 'a.pdf', byte_size: 1, sha256: 'a' * 64, chunk_size: 1, chunk_count: 1, status: 'accepted',
                                      document_id: document.id, request_line_id: copy.id, expires_at: 1.day.from_now)
      Accounting::DocumentLink.create!(document: document, target: line)

      described_class.call

      expect(copy.reload.state).to eq('provided')
      expect(upload.reload.request_line_id).to eq(copy.id)
    end

    it 'leaves an open request open' do
      described_class.call
      expect(copy.reload.state).to eq('open')
    end

    it 'opens a task for the accountant from an answer without a document, and books nothing' do
      copy.update!(state: 'explained', answered_by_id: person.id, answered_at: Time.current, answer_reason: 'personal', answer_note: 'my lunch')

      expect { described_class.call }.not_to change(Accounting::JournalEntry, :count)

      task = Accounting::Task.find(copy.reload.task_id)
      expect(task).to have_attributes(kind: 'missing_document', target: line)
      expect(task.title).to include('no invoice')
      expect(task.description.to_s).to include('my lunch')
      expect(Accounting::AuditLog.where(action: 'portal_document_request_answered').count).to eq(1)
      described_class.call
      expect(Accounting::Task.count).to eq(1) # once
    end
  end

  describe PortalAdmin::RemindDocumentRequests do
    before do
      PortalAdmin::RequestDocuments.call(entity: entity, lines: [ line ], by: staff, due_on: Date.current + 2)
      ActionMailer::Base.deliveries.clear
    end

    let(:request) { Portal::DocumentRequest.sole }

    it 'reminds, with a count and nothing else, when the answer is due within three days' do
      described_class.call

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(ActionMailer::Base.deliveries.last.body.to_s).not_to include('ACME')
      expect(request.reload.last_reminder_on).to eq(Date.current)
    end

    it 'does not remind twice within three days' do
      described_class.call
      described_class.call
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it 'reminds again after three days, also when the date is past' do
      request.update!(due_on: Date.current - 10, last_reminder_on: Date.current - 3)
      described_class.call
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it 'says nothing when the due date is far, or when nothing is open any more' do
      request.update!(due_on: Date.current + 30)
      described_class.call
      request.update!(due_on: Date.current + 1)
      Portal::DocumentRequestLine.update_all(state: 'provided')
      described_class.call
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'says nothing to someone who chose not to be told' do
      person.update!(notification_frequency: 'off')
      described_class.call
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
