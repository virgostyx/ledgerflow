require 'rails_helper'

RSpec.describe FlashMessageComponent, type: :component do
  let(:message) { 'Operation successful' }

  context 'with notice type' do
    before { render_inline(described_class.new(type: :notice, message: message)) }

    it 'renders the message' do
      expect(page).to have_text('Operation successful')
    end

    it 'applies success styling' do
      expect(page).to have_css('.bg-emerald-50')
      expect(page).to have_css('.border-emerald-200')
    end

    it 'has the flash data controller' do
      expect(page).to have_css('[data-controller="flash"]')
    end

    it 'sets the duration data value' do
      expect(page).to have_css('[data-flash-duration-value="5000"]')
    end

    it 'has a close button' do
      expect(page).to have_css('button[data-action="click->flash#close"]')
    end

    it 'has a progress bar target' do
      expect(page).to have_css('[data-flash-target="progressBar"]')
    end

    it 'has mouseenter/mouseleave actions' do
      expect(page).to have_css('[data-action*="mouseenter->flash#pause"]')
      expect(page).to have_css('[data-action*="mouseleave->flash#resume"]')
    end
  end

  context 'with success type' do
    before { render_inline(described_class.new(type: :success, message: message)) }

    it 'applies success styling' do
      expect(page).to have_css('.bg-emerald-50')
    end
  end

  context 'with alert type' do
    before { render_inline(described_class.new(type: :alert, message: message)) }

    it 'applies warning styling' do
      expect(page).to have_css('.bg-amber-50')
      expect(page).to have_css('.border-amber-200')
    end
  end

  context 'with warning type' do
    before { render_inline(described_class.new(type: :warning, message: message)) }

    it 'applies warning styling' do
      expect(page).to have_css('.bg-amber-50')
    end
  end

  context 'with error type' do
    before { render_inline(described_class.new(type: :error, message: message)) }

    it 'applies danger styling' do
      expect(page).to have_css('.bg-red-50')
      expect(page).to have_css('.border-red-200')
    end
  end

  context 'with info type' do
    before { render_inline(described_class.new(type: :info, message: message)) }

    it 'applies info styling' do
      expect(page).to have_css('.bg-primary-50')
      expect(page).to have_css('.border-primary-200')
    end
  end

  context 'with custom duration' do
    before { render_inline(described_class.new(type: :notice, message: message, duration: 8000)) }

    it 'passes duration to controller' do
      expect(page).to have_css('[data-flash-duration-value="8000"]')
    end
  end
end
