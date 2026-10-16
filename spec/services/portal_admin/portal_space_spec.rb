require 'rails_helper'

# B02c, "Espace du cabinet": what the firm sees of the portal of a company at a glance, with its indicators in SQL; and the weekly summary sent to the clients (counters and links only).
RSpec.describe 'Firm space of the portal' do
  include_context 'with entity'

  let(:staff)  { create(:user) }
  let(:jane)   { create(:portal_user, full_name: 'Jane Client') }
  let(:joe)    { create(:portal_user, full_name: 'Joe Colleague') }

  before do
    [ jane, joe ].each { |p| Portal::Grant.create!(portal_user: p, entity_id: entity.id, role: 'director', capabilities: Portal::CAPABILITIES) }
    ActionMailer::Base.deliveries.clear
  end

  def question(asked_at:, answered_after: nil, **attrs)
    q = Portal::Question.create!({ entity_id: entity.id, task_id: 1, title: 'Q', answer_type: 'text', asked_at: asked_at, asked_by_id: staff.id }.merge(attrs))
    if answered_after
      Portal::Answer.create!(question: q, portal_user: jane, entity_id: entity.id, answered_at: asked_at + answered_after)
      q.update!(status: 'answered')
    end
    q
  end

  describe PortalAdmin::SpaceIndicators do
    it 'gives the average time to answer and the share answered within seven days, in SQL' do
      question(asked_at: 20.days.ago, answered_after: 2.days)
      question(asked_at: 20.days.ago, answered_after: 4.days)
      question(asked_at: 20.days.ago, answered_after: 12.days)
      question(asked_at: 3.days.ago) # waiting: not counted

      result = described_class.call(entity: entity)

      expect(result[:average_days_to_answer]).to eq(BigDecimal('6.0'))
      expect(result[:answered_within_7_days_rate]).to eq(BigDecimal('66.7'))
    end

    it 'is empty when no question was answered' do
      expect(described_class.call(entity: entity)).to include(average_days_to_answer: nil, answered_within_7_days_rate: nil)
    end

    it 'counts the questions waiting, by age' do
      question(asked_at: 2.days.ago)
      question(asked_at: 9.days.ago)
      question(asked_at: 20.days.ago, status: 'closed')

      expect(described_class.call(entity: entity)[:waiting_by_age]).to eq('0-7 days' => 1, '8-14 days' => 1, 'over 14 days' => 0)
    end

    it 'names the clients who did not come for 30 days, and those who never did' do
      Portal::Session.create!(portal_user: jane, token_digest: 'a', last_seen_at: 2.days.ago)
      Portal::Session.create!(portal_user: joe, token_digest: 'b', last_seen_at: 45.days.ago)

      expect(described_class.call(entity: entity)[:inactive_people].map(&:full_name)).to eq([ 'Joe Colleague' ])
    end
  end

  describe PortalAdmin::WeeklySummary do
    it 'gives each person the counters of what waits for them, with a link, and nothing else' do
      question(asked_at: 1.day.ago, title: 'Is it professional? (secret)')
      question(asked_at: 1.day.ago, title: 'Another')
      request = Portal::DocumentRequest.create!(entity_id: entity.id, requested_by: staff)
      request.lines.create!(entity_id: entity.id, bank_transaction_id: 1, line_date: Date.current, amount: 1, label: 'ACME secret')

      described_class.call

      mail = ActionMailer::Base.deliveries.find { |m| m.to == [ jane.email ] }
      body = mail.body.to_s
      expect(body).to include('2 questions', '1 document')
      expect(body).not_to include('secret', 'ACME', 'professional')
    end

    it 'sends nothing when nothing waits, nor to someone who chose not to be told' do
      described_class.call
      expect(ActionMailer::Base.deliveries).to be_empty

      question(asked_at: 1.day.ago)
      jane.update!(notification_frequency: 'off')
      joe.update!(notification_frequency: 'off')
      described_class.call
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'does not count what a person may not answer, nor what belongs to another company' do
      other = create(:entity)
      Portal::Question.create!(entity_id: other.id, task_id: 1, title: 'Foreign', answer_type: 'text', asked_at: 1.day.ago, asked_by_id: staff.id)
      Portal::Grant.where(portal_user: joe).update_all(capabilities: %w[publications.view])
      question(asked_at: 1.day.ago)

      described_class.call

      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to eq([ jane.email ])
      expect(ActionMailer::Base.deliveries.first.body.to_s).to include('1 question')
    end
  end
end
