require 'rails_helper'

RSpec.describe Ui::MusicPlayerComponent, type: :component do
  before { render_inline(described_class.new) }

  it 'has the music-player data controller' do
    expect(page).to have_css('[data-controller="music-player"]')
  end

  it 'is marked data-turbo-permanent for continuous audio' do
    expect(page).to have_css('[data-turbo-permanent]')
  end

  it 'renders the FAB toggle button' do
    expect(page).to have_css('[data-action*="music-player#toggle"]')
  end

  it 'panel is hidden by default' do
    expect(page).to have_css('[data-music-player-target="panel"].hidden')
  end

  it 'renders all 5 SomaFM stations' do
    %w[Groove\ Salad Secret\ Agent Space\ Station Lush Drone\ Zone].each do |station|
      expect(page).to have_text(station)
    end
  end

  it 'has a play/pause toggle button' do
    expect(page).to have_css('[data-action*="music-player#togglePlay"]')
  end

  it 'has prev/next station buttons' do
    expect(page).to have_css('[data-action*="music-player#prevStation"]')
    expect(page).to have_css('[data-action*="music-player#nextStation"]')
  end

  it 'has a volume slider' do
    expect(page).to have_css('[data-music-player-target="volumeSlider"]')
  end

  it 'renders station items as buttons' do
    expect(page).to have_css('[data-music-player-target="stationItem"]', minimum: 5)
  end
end
