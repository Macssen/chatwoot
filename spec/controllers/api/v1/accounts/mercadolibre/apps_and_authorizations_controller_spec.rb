require 'rails_helper'

RSpec.describe 'MercadoLibre account app API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/mercadolibre" }

  describe 'PATCH /mercadolibre/app' do
    it 'stores the account app and never returns the secret' do
      patch "#{base_url}/app", params: { app_id: 123_456, app_secret: 's3cr3t' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('configured' => true, 'app_id' => 123_456)
      expect(response.body).not_to include('s3cr3t')
      expect(account.reload.mercadolibre_app.app_secret).to eq('s3cr3t')
    end

    it 'is restricted to administrators' do
      patch "#{base_url}/app", params: { app_id: 123_456, app_secret: 's3cr3t' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /mercadolibre/authorization' do
    it 'fails while the account has no app' do
      post "#{base_url}/authorization", params: { flow: 'pre_sale' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'builds the authorization url with the account app' do
      create(:mercadolibre_app, account: account, app_id: 777)

      post "#{base_url}/authorization", params: { flow: 'post_sale' }, headers: administrator.create_new_auth_token, as: :json

      url = response.parsed_body['url']
      expect(url).to start_with('https://auth.mercadolibre.com.ar/authorization?')
      expect(url).to include('client_id=777')
      expect(url).to include(CGI.escape("#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/mercadolibre/callback"))
    end
  end
end
