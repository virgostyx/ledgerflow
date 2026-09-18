require 'rails_helper'

RSpec.describe 'Favicon', type: :request do
  describe 'GET /favicon.ico' do
    it 'redirige vers /icon.png' do
      get '/favicon.ico'
      expect(response).to redirect_to('/icon.png')
    end
  end
end
