require 'rails_helper'

RSpec.describe Layouts::DashboardKpiComponent, type: :component do
  let(:kpis) do
    [
      { title: 'Invoices to validate', value: 5,              icon: :document_text, color: :amber  },
      { title: 'Treasury balance',     value: '€12,345.00',   icon: :banknotes,     color: :green  },
      { title: 'Draft entries',        value: 3,              icon: :book_open,     color: :primary }
    ]
  end

  before { render_inline(described_class.new(kpis: kpis)) }

  it 'renders the title of each KPI' do
    expect(page).to have_text('Invoices to validate')
    expect(page).to have_text('Treasury balance')
    expect(page).to have_text('Draft entries')
  end

  it 'renders the values' do
    expect(page).to have_text('5')
    expect(page).to have_text('€12,345.00')
    expect(page).to have_text('3')
  end

  it 'renders a responsive grid wrapper' do
    expect(page).to have_css('.grid')
  end

  it 'renders each KPI as a Stats::KpiCardComponent' do
    expect(page).to have_css('[role="article"]', count: 3)
  end
end
