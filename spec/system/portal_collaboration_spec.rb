require 'rails_helper'

# B02c, the whole journey in a real browser: a question, its answer, accounts published for approval, the client opens the documents and approves; the proof is sealed and verifies.
RSpec.describe 'Question, answer, publication, approval', type: :system, js: true, portal_browser: true do
  include_context 'with signing keys directory'

  let(:entity)   { create(:entity, name: 'Acme Ltd') }
  let(:staff)    { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:director) { create(:portal_user, full_name: 'Dora Director', identity_verified_at: Time.current, identity_verified_by: staff) }
  let!(:line)    { ActsAsTenant.with_tenant(entity) { create(:bank_transaction, counterparty_name: 'ACME Supplies') } }

  around do |example|
    previous = [ Rails.configuration.x.portal_host, Capybara.app_host, Capybara.always_include_port ]
    Rails.configuration.x.portal_host = 'portal.localhost'
    Capybara.app_host = 'http://portal.localhost'
    Capybara.always_include_port = true
    example.run
  ensure
    Rails.configuration.x.portal_host, Capybara.app_host, Capybara.always_include_port = previous
  end

  before do
    Portal::Grant.create!(portal_user: director, entity_id: entity.id, role: 'director', capabilities: Portal::CAPABILITIES)
    Ledger::SigningKeys.generate!
  end

  def sign_in!
    visit '/sign_in'
    fill_in 'Email', with: director.email
    fill_in 'Password', with: 'correct horse battery'
    click_button 'Continue'
    fill_in 'Code', with: Totp.code(director.totp_secret)
    click_button 'Sign in'
    expect(page).to have_content('Signed in as')
  end

  it 'goes from the question to the sealed approval' do
    asked = PortalAdmin::AskQuestion.call(entity: entity, by: staff, title: 'Is this expense professional?', answer_type: 'single', target: line,
                                          choices: [ { key: 'yes', label: 'Yes', suggested_treatment: 'professional: expense' }, { key: 'no', label: 'No' } ])
    expect(asked).to be_success
    sign_in!

    visit '/questions'
    click_link 'Answer'
    expect(page).to have_content('ACME Supplies')
    choose 'Yes'
    click_button 'Send my answer'
    expect(page).to have_content('Thank you')

    PortalAdmin::SyncAnswers.call
    comment = ActsAsTenant.with_tenant(entity) { Accounting::Task.find(asked[:task].id).comments.sole }
    expect(comment.body).to include('Suggestion (not applied): professional: expense')

    publication = PortalAdmin::Publish.call(entity: entity, kind: 'situation', title: 'Accounts 2026', by: staff, requires_approval: true, approvers: [ director ],
                                            files: [ { filename: 'balance.pdf', content_type: 'application/pdf', data: Prawn::Document.new { |d| d.text 'Balance' }.render } ])[:publication]
    visit "/publications/#{publication.token}"
    expect(page).to have_content('Open every document before deciding.')
    expect(page).to have_button('Send my decision', disabled: true)

    href = page.find_link('balance.pdf')[:href]
    page.driver.browser.execute_async_script("fetch(arguments[0]).then(() => arguments[1](true))", href) # opening the document, as the browser would
    visit "/publications/#{publication.token}"
    expect(page).not_to have_content('Open every document before deciding.')

    choose 'Approve'
    check 'I confirm that I opened these documents'
    click_button 'Send my decision'
    expect(page).to have_content('Thank you. Your decision was recorded.')

    PortalAdmin::SealApprovals.call
    approval = Portal::Approval.sole
    expect(approval).to be_sealed
    expect(PortalAdmin::VerifyApproval.call(approval)).to be_valid
  end
end
