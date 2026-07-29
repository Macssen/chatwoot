require 'rails_helper'

# Devise Token Auth's native registration routes are disabled via
# `skip: [:registrations]` in config/routes.rb, since signup goes through
# POST /api/v1/accounts.
RSpec.describe 'Devise Token Auth registration routes', type: :request do
  describe 'POST /auth' do
    it 'is not routable and does not create a user' do
      expect do
        post '/auth', params: { email: 'new-signup@example.com', password: 'Password1!' }, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /auth' do
    it 'is not routable' do
      delete '/auth', as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /auth/sign_in' do
    it 'stays routable so disabling registrations does not break login' do
      post '/auth/sign_in', params: { email: 'nobody@example.com', password: 'wrong' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
