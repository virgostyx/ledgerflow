require 'rails_helper'

RSpec.describe Stats::KpiCardComponent, type: :component do
  def render_card(**opts)
    render_inline(described_class.new(**opts))
  end

  it 'renders the title' do
    render_card(title: 'Draft Invoices', value: 5)
    expect(page).to have_text('Draft Invoices')
  end

  it 'renders the value prominently' do
    render_card(title: 'Balance', value: '€12,345.00')
    expect(page).to have_text('€12,345.00')
    expect(page).to have_css('.text-3xl')
  end

  it 'renders an icon square' do
    render_card(title: 'KPI', value: 1, icon: :chart_bar, color: :primary)
    expect(page).to have_css('svg')
    expect(page).to have_css('.rounded-lg')
  end

  it 'applies primary color classes for :primary' do
    render_card(title: 'KPI', value: 1, color: :primary)
    expect(page).to have_css('[class*="primary"]')
  end

  it 'applies green color classes for :green' do
    render_card(title: 'KPI', value: 1, color: :green)
    expect(page).to have_css('[class*="green"]')
  end

  it 'applies red color classes for :red' do
    render_card(title: 'KPI', value: 1, color: :red)
    expect(page).to have_css('[class*="red"]')
  end

  it 'applies blue color classes for :blue' do
    render_card(title: 'KPI', value: 1, color: :blue)
    expect(page).to have_css('[class*="blue"]')
  end

  it 'applies amber color classes for :amber' do
    render_card(title: 'KPI', value: 1, color: :amber)
    expect(page).to have_css('[class*="amber"]')
  end

  it 'renders subtitle when provided' do
    render_card(title: 'KPI', value: 1, subtitle: 'Current fiscal year')
    expect(page).to have_text('Current fiscal year')
  end

  it 'does not render subtitle when absent' do
    render_card(title: 'KPI', value: 1)
    expect(page).not_to have_css('.text-xs.text-gray-500', text: /fiscal/)
  end

  it 'renders an upward trend' do
    render_card(title: 'KPI', value: 1, trend: { direction: :up, value: '+8%', positive: true })
    expect(page).to have_text('+8%')
    expect(page).to have_css('[class*="green"]')
  end

  it 'renders a downward trend' do
    render_card(title: 'KPI', value: 1, trend: { direction: :down, value: '-3%', positive: false })
    expect(page).to have_text('-3%')
    expect(page).to have_css('[class*="red"]')
  end

  it 'shows "vs. last month" label with trend' do
    render_card(title: 'KPI', value: 1, trend: { direction: :up, value: '+5%', positive: true })
    expect(page).to have_text('vs. last month')
  end

  it 'does not render trend section when absent' do
    render_card(title: 'KPI', value: 1)
    expect(page).not_to have_text('vs. last month')
  end

  it 'has the correct container classes' do
    render_card(title: 'KPI', value: 1)
    expect(page).to have_css('.bg-white.rounded-lg.border.border-gray-200')
  end

  it 'is accessible with role article' do
    render_card(title: 'Treasury Balance', value: '€0.00')
    expect(page).to have_css('[role="article"]')
  end
end
