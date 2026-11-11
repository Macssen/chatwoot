require 'rails_helper'

# Devise's native registration routes are disabled via `skip: [:registrations]`
# in config/routes.rb for both Devise mounts: signup goes through
# POST /api/v1/accounts and super admins are provisioned separately.
RSpec.describe 'Devise registration routes', type: :request do
  it 'does not route to any registrations controller' do
    registration_routes = Rails.application.routes.routes.select { |route| route.defaults[:controller].to_s.end_with?('registrations') }

    expect(registration_routes.map { |route| route.path.spec.to_s }).to be_empty
  end

  describe 'POST /auth' do
    it 'is not routable and does not create a user' do
      expect do
        post '/auth', params: { email: 'new-signup@example.com', password: 'Password1!' }, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /super_admin/sign_up' do
    it 'is not routable' do
      get '/super_admin/sign_up'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /super_admin' do
    it 'is not routable and does not create a user' do
      expect do
        post '/super_admin', params: { super_admin: { email: 'new-signup@example.com', password: 'Password1!' } }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /auth/sign_in' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'Password1!') }

    it 'still signs in a confirmed user' do
      post '/auth/sign_in', params: { email: user.email, password: 'Password1!' }, as: :json

      expect(response).to have_http_status(:success)
      expect(response.headers['access-token']).to be_present
    end

    it 'rejects unknown credentials' do
      post '/auth/sign_in', params: { email: 'nobody@example.com', password: 'wrong' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    context 'when the user has not confirmed the account' do
      let(:user) { create(:user, account: account, password: 'Password1!', skip_confirmation: false) }

      it 'asks for confirmation when the password is correct' do
        post '/auth/sign_in', params: { email: user.email, password: 'Password1!' }, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_code']).to eq('user_not_confirmed')
      end

      it 'responds like any failed login when the password is wrong' do
        post '/auth/sign_in', params: { email: user.email, password: 'Wrong-pass1!' }, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error_code']).to be_nil
        expect(response.body).not_to include(user.email)
      end
    end
  end
end
