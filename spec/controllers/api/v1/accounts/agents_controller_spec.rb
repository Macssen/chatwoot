require 'rails_helper'

RSpec.describe 'Agents API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, custom_attributes: { test: 'test' }, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, email: 'exists@example.com', role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/agents' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all agents of account' do
        get "/api/v1/accounts/#{account.id}/agents",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.parsed_body.size).to eq(account.users.count)
      end

      it 'returns custom fields on agents if present' do
        agent.update(custom_attributes: { test: 'test' })

        get "/api/v1/accounts/#{account.id}/agents",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data.first['custom_attributes']['test']).to eq('test')
      end
    end

    context 'when it is an agent with a custom role' do
      let!(:restricted_agent) { create(:user, account: account, role: :agent) }
      let!(:inbox_mate) { create(:user, account: account, role: :agent) }
      let!(:unrelated_agent) { create(:user, account: account, role: :agent) }
      let(:inbox) { create(:inbox, account: account) }
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

      before do
        create(:inbox_member, user: restricted_agent, inbox: inbox)
        create(:inbox_member, user: inbox_mate, inbox: inbox)
        restricted_agent.account_users.find_by(account_id: account.id).update!(custom_role: custom_role)
      end

      it 'returns only inbox mates, administrators and the agent itself' do
        get "/api/v1/accounts/#{account.id}/agents",
            headers: restricted_agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        agent_ids = response.parsed_body.map { |a| a['id'] }
        expect(agent_ids).to contain_exactly(restricted_agent.id, inbox_mate.id, admin.id)
        expect(agent_ids).not_to include(unrelated_agent.id)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/agents/:id' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'returns unauthorized for agents' do
        delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'deletes the agent and user object if associated with only one account' do
        expect(account.users).to include(other_agent)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end

        expect(response).to have_http_status(:success)
        expect(account.reload.users).not_to include(other_agent)
      end

      it 'deletes only the agent object when user is associated with multiple accounts' do
        other_account = create(:account)
        create(:account_user, account_id: other_account.id, user_id: other_agent.id)

        perform_enqueued_jobs(only: DeleteObjectJob) do
          delete "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end

        expect(response).to have_http_status(:success)
        expect(account.reload.users).not_to include(other_agent)
        expect(other_agent.account_users.count).to eq(1) # Should only be associated with other_account now
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/agents/:id' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      params = { name: 'TestUser' }

      it 'returns unauthorized for agents' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'modifies an agent name' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(other_agent.reload.name).to eq(params[:name])
      end

      it 'modifies an agents account user attributes' do
        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { role: 'administrator', availability: 'busy', auto_offline: false },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_data = response.parsed_body
        expect(response_data['role']).to eq('administrator')
        expect(response_data['availability_status']).to eq('busy')
        expect(response_data['auto_offline']).to be(false)
        expect(other_agent.account_users.first.role).to eq('administrator')
      end

      it 'assigns a custom role sent as a top-level param' do
        custom_role = create(:custom_role, account: account)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { agent: { role: 'agent' }, custom_role_id: custom_role.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.account_users.first.custom_role_id).to eq(custom_role.id)
      end

      it 'clears the custom role when custom_role_id is null' do
        custom_role = create(:custom_role, account: account)
        other_agent.account_users.first.update!(custom_role: custom_role)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { agent: { role: 'agent' }, custom_role_id: nil },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.account_users.first.reload.custom_role_id).to be_nil
      end

      it 'keeps the custom role when custom_role_id is not sent' do
        custom_role = create(:custom_role, account: account)
        other_agent.account_users.first.update!(custom_role: custom_role)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { agent: { name: 'TestUser' } },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(other_agent.account_users.first.reload.custom_role_id).to eq(custom_role.id)
      end

      it 'returns not found for a custom role belonging to another account' do
        other_account_role = create(:custom_role)

        put "/api/v1/accounts/#{account.id}/agents/#{other_agent.id}",
            params: { agent: { role: 'agent' }, custom_role_id: other_account_role.id },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
        expect(other_agent.account_users.first.reload.custom_role_id).to be_nil
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agents' do
    let(:other_agent) { create(:user, account: account, role: :agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      params = { name: 'NewUser', email: Faker::Internet.email, role: :agent }

      it 'returns unauthorized for agents' do
        post "/api/v1/accounts/#{account.id}/agents",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new agent' do
        post "/api/v1/accounts/#{account.id}/agents",
             params: params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response).to conform_schema(200)
        expect(response.parsed_body['email']).to eq(params[:email])
        expect(account.users.last.name).to eq('NewUser')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/agents/bulk_create' do
    let(:emails) { ['test1@example.com', 'test2@example.com', 'test3@example.com'] }
    let(:bulk_create_params) { { emails: emails } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as admin' do
      it 'creates multiple agents successfully' do
        expect do
          post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: bulk_create_params, headers: admin.create_new_auth_token
        end.to change(User, :count).by(3)

        expect(response).to have_http_status(:ok)
      end

      it 'ignores errors if account_user already exists' do
        params = { emails: ['exists@example.com', 'test1@example.com', 'test2@example.com'] }

        expect do
          post "/api/v1/accounts/#{account.id}/agents/bulk_create", params: params,
                                                                    headers: admin.create_new_auth_token
        end.to change(User, :count).by(2)

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
