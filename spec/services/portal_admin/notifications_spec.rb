require 'rails_helper'

# B02a: the e-mails to the clients carry counters and links, never an amount or a name of a third party; the person chooses how often, security alerts excepted.
RSpec.describe 'Portal notifications' do
  include_context 'with entity'

  let(:staff) { create(:user) }
  let(:file)  { { filename: 'a.pdf', content_type: 'application/pdf', data: '%PDF-1.4' } }
  let!(:ann)  { create(:portal_user, email: 'ann@client.example') }
  let!(:bob)  { create(:portal_user, email: 'bob@client.example', notification_frequency: 'daily') }
  let!(:cat)  { create(:portal_user, email: 'cat@client.example', notification_frequency: 'off') }
  let!(:dan)  { create(:portal_user, email: 'dan@client.example') }

  before do
    [ ann, bob, cat ].each { |u| Portal::Grant.create!(portal_user: u, entity_id: entity.id, role: 'director', capabilities: %w[publications.view]) }
    Portal::Grant.create!(portal_user: dan, entity_id: entity.id, role: 'reader', capabilities: [])
    ActionMailer::Base.deliveries.clear
  end

  def publish(**args) = PortalAdmin::Publish.call(entity: entity, kind: 'monthly_report', title: 'Invoice from ACME Ltd for 12 345,00 EUR', files: [ file ], by: staff, **args)

  it 'tells at once those who asked for it and may see publications, with a link and no figure, no title, no name' do
    publish

    mails = ActionMailer::Base.deliveries
    expect(mails.map(&:to).flatten).to contain_exactly('ann@client.example')
    body = mails.first.body.to_s
    expect(body).to match(%r{https?://#{Regexp.escape(Rails.configuration.x.portal_host)}\S*/publications})
    expect(body).not_to match(/ACME|12 345|EUR/)
    expect(mails.first.subject).not_to match(/ACME|12 345/)
  end

  it 'tells only the recipients when a publication is addressed to some' do
    publish(recipients: [ ann ])
    expect(ActionMailer::Base.deliveries.map(&:to).flatten).to eq([ 'ann@client.example' ])
    ActionMailer::Base.deliveries.clear
    publish(recipients: [ bob ])
    expect(ActionMailer::Base.deliveries).to be_empty # bob wants a daily digest
  end

  it 'does not fail the publication when the mail cannot be sent' do
    allow_any_instance_of(Portal::NotificationMailer).to receive(:new_publications).and_raise(Net::SMTPFatalError)
    expect(publish).to be_success
  end

  it 'gathers the day in one mail for those who asked for a digest, once' do
    publish
    publish
    ActionMailer::Base.deliveries.clear

    PortalAdmin::DailyDigest.call
    PortalAdmin::DailyDigest.call

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.first
    expect(mail.to).to eq([ 'bob@client.example' ])
    expect(mail.body.to_s).to include('2 new publications')
  end

  it 'sends no digest when nothing is new' do
    PortalAdmin::DailyDigest.call
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
