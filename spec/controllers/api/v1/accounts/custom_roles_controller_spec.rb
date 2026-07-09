require 'rails_helper'

RSpec.describe 'Custom Roles API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

  describe 'GET /api/v1/accounts/{account.id}/custom_roles' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/custom_roles"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/custom_roles",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'returns all custom roles of the account' do
        get "/api/v1/accounts/#{account.id}/custom_roles",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first['id']).to eq(custom_role.id)
        expect(response.parsed_body.first['permissions']).to eq(['conversation_manage'])
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/custom_roles/:id' do
    context 'when it is an administrator' do
      it 'returns the custom role' do
        get "/api/v1/accounts/#{account.id}/custom_roles/#{custom_role.id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(custom_role.id)
      end

      it 'returns not found for a custom role of another account' do
        other_role = create(:custom_role)

        get "/api/v1/accounts/#{account.id}/custom_roles/#{other_role.id}",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/custom_roles' do
    context 'when it is an agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/custom_roles",
             params: { custom_role: { name: 'Support', permissions: ['conversation_manage'] } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'creates a custom role' do
        post "/api/v1/accounts/#{account.id}/custom_roles",
             params: { custom_role: { name: 'Support', description: 'L1', permissions: %w[conversation_participating_manage] } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(account.custom_roles.count).to eq(2)
        expect(response.parsed_body['permissions']).to eq(['conversation_participating_manage'])
      end

      it 'rejects invalid permissions' do
        post "/api/v1/accounts/#{account.id}/custom_roles",
             params: { custom_role: { name: 'Support', permissions: ['manage_everything'] } },
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/custom_roles/:id' do
    context 'when it is an administrator' do
      it 'updates the custom role' do
        patch "/api/v1/accounts/#{account.id}/custom_roles/#{custom_role.id}",
              params: { custom_role: { name: 'Renamed', permissions: ['contact_manage'] } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(custom_role.reload.name).to eq('Renamed')
        expect(custom_role.reload.permissions).to eq(['contact_manage'])
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/custom_roles/:id' do
    context 'when it is an agent' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/custom_roles/#{custom_role.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      it 'destroys the custom role' do
        delete "/api/v1/accounts/#{account.id}/custom_roles/#{custom_role.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(account.custom_roles.count).to eq(0)
      end
    end
  end
end
