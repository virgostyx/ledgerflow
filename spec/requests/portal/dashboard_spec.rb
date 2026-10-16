require 'rails_helper'

# B02c, the client's dashboard: figures of the latest published snapshot only, each with its date and "provisional" note, a small curve with a text alternative and a table, a word of the accountant
# once approved, in the language of the person, and nothing that names a third party. A person sees only the companies where they may.
RSpec.describe 'Portal dashboard', type: :request do
  let(:entity) { create(:entity, name: 'Acme Ltd') }
  let(:person) { create(:portal_user) }

  def grant(capabilities: %w[dashboard.view], entity_id: entity.id)
    Portal::Grant.create!(portal_user: person, entity_id: entity_id, role: 'director', capabilities: capabilities)
  end

  def sign_in!
    post '/session', params: { email: person.email, password: 'correct horse battery' }
    post '/second_factor/challenge', params: { code: Totp.code(person.totp_secret) }
  end

  def snapshot(for_entity = entity, **attrs)
    months = (0...12).map { |i| (Date.new(2026, 5, 1) << (11 - i)).strftime('%Y-%m') }
    Portal::Snapshot.create!({ entity_id: for_entity.id, period_start: Date.new(2026, 5, 1), period_end: Date.new(2026, 5, 15), provisional: true, generated_at: Time.zone.local(2026, 5, 15, 3), known_at: Time.zone.local(2026, 5, 15, 3),
      sha256: 'a' * 64, status: 'published', published_at: Time.zone.local(2026, 5, 15, 3),
      indicators: { 'cash' => '1500.00', 'sales_month' => '1000.00', 'sales_previous_month' => '800.00', 'sales_last_year' => '600.00', 'result_ytd' => '1660.00', 'receivables_overdue' => '250.00',
                    'receivables_overdue_count' => 1, 'payables_30_days' => '90.00' },
      series: { 'sales' => months.each_with_index.map { |m, i| { 'month' => m, 'value' => (i * 100).to_s + '.00' } }, 'cash' => months.map { |m| { 'month' => m, 'value' => '1500.00' } } } }.merge(attrs))
  end

  before { host! Rails.configuration.x.portal_host }

  it 'shows the figures with their date, the provisional note, a plain-language help, a curve and its table' do
    grant
    snapshot
    sign_in!

    get '/dashboard'

    expect(response.body).to include('Acme Ltd', '1,500.00', '1,000.00', '250.00', 'provisional', '2026-05-15')
    expect(response.body).to include('Overdue receivables', 'invoices from your customers that are paid late')
    expect(response.body).to match(/<svg[^>]*role="img"[^>]*aria-label=/)
    expect(response.body).to include('<table', '2025-06')
  end

  it 'does not say "provisional" for a closed year' do
    grant
    snapshot(provisional: false)
    sign_in!
    get '/dashboard'
    expect(response.body).not_to include('provisional')
  end

  it 'shows the latest published snapshot, not a draft waiting for the firm' do
    grant
    snapshot(indicators: { 'cash' => '111.00' }, generated_at: Time.zone.local(2026, 5, 14))
    snapshot(indicators: { 'cash' => '999.00' }, status: 'pending_review', generated_at: Time.zone.local(2026, 5, 16))
    sign_in!
    get '/dashboard'
    expect(response.body).to include('111.00')
    expect(response.body).not_to include('999.00')
  end

  it 'shows the word of the accountant only once a person approved it' do
    grant
    snap = snapshot(accountant_word: 'A fine month, well done.', word_source: 'human')
    sign_in!
    get '/dashboard'
    expect(response.body).not_to include('A fine month')

    snap.update!(word_approved_at: Time.current)
    get '/dashboard'
    expect(response.body).to include('A fine month, well done.')
  end

  it 'speaks French and Dutch, with the text alternatives too' do
    grant
    snapshot
    person.update!(locale: 'fr')
    sign_in!
    get '/dashboard'
    expect(response.body).to include('Trésorerie', 'Créances clients échues', 'données provisoires')
    expect(response.body).to match(/aria-label="[^"]*Ventes/)

    person.update!(locale: 'nl')
    get '/dashboard'
    expect(response.body).to include('Beschikbare liquiditeit', 'voorlopige gegevens')
    expect(response.body).to match(/aria-label="[^"]*Verkopen/)
  end

  it 'keeps the companies of a person apart' do
    other = create(:entity, name: 'Other Co')
    grant
    grant(entity_id: other.id)
    snapshot
    snapshot(other, indicators: { 'cash' => '42.00' })
    sign_in!

    get '/dashboard'
    expect(response.body).to include('Acme Ltd', 'Other Co', '1,500.00', '42.00')
    expect(response.body.index('Acme Ltd')).to be < response.body.index('1,500.00')
  end

  it 'shows nothing without the right, nor for a company that turned the feature off' do
    grant(capabilities: %w[publications.view])
    snapshot
    sign_in!
    get '/dashboard'
    expect(response.body).not_to include('1,500.00')

    person.grants.destroy_all
    grant
    entity.update!(features: { 'b02c' => false })
    get '/dashboard'
    expect(response.body).not_to include('1,500.00')
  end

  it 'says so when there is nothing to show yet' do
    grant
    sign_in!
    get '/dashboard'
    expect(response.body).to include('not ready yet')
  end

  it 'never names a third party' do
    grant
    snapshot
    sign_in!
    get '/dashboard'
    expect(response.body).not_to match(/Secret|IBAN/i)
  end

  it 'gives the dashboard as a PDF, made of the snapshot alone' do
    grant
    snapshot
    sign_in!

    get "/dashboard.pdf?company=#{entity.id}"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join(' ')
    expect(text).to include('Acme Ltd', '1,500.00', '2026-05-15')
  end

  it 'does not give the PDF of a company the person cannot see' do
    grant
    other = create(:entity)
    snapshot(other)
    sign_in!
    get "/dashboard.pdf?company=#{other.id}"
    expect(response).to have_http_status(:not_found)
  end
end
