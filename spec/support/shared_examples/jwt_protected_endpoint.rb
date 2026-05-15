RSpec.shared_examples 'a JWT-protected endpoint' do
  context 'without token' do
    it 'returns 401' do
      subject
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with invalid token' do
    let(:jwt_token) { 'invalid.token.here' }

    it 'returns 401' do
      subject
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
