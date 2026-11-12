require 'rails_helper'

RSpec.describe 'Canned Responses API', type: :request do
  let(:account) { create(:account) }

  before do
    create(:canned_response, account: account, content: 'Hey {{ contact.name }}, Thanks for reaching out', short_code: 'name-short-code')
  end

  describe 'GET /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns all the canned responses' do
        get "/api/v1/accounts/#{account.id}/canned_responses",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to eq(account.canned_responses.pluck(:id))
        expect(response.parsed_body.first['created_by']).to be_nil
      end

      it 'returns all the canned responses the user searched for' do
        cr1 = account.canned_responses.first
        create(:canned_response, account: account, content: 'Great! Looking forward', short_code: 'short-code')
        cr2 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'content-with-thanks')
        cr3 = create(:canned_response, account: account, content: 'Thanks for reaching out', short_code: 'Thanks')

        params = { search: 'thanks' }

        get "/api/v1/accounts/#{account.id}/canned_responses",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to eq([cr3, cr2, cr1].map(&:id))
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/canned_responses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/canned_responses"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'creates a new canned response' do
        params = { short_code: 'short', content: 'content' }

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.count).to eq(2)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:canned_response) { CannedResponse.last }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for an agent' do
        params = { short_code: 'B' }

        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'updates an existing canned response when administrator' do
        params = { short_code: 'B' }

        put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
            params: params,
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(canned_response.reload.short_code).to eq('B')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/canned_responses/:id' do
    let(:canned_response) { CannedResponse.last }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for an agent' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'destroys the canned response when administrator' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(CannedResponse.count).to eq(0)
      end
    end
  end

  describe 'ownership and role permissions' do
    let(:administrator) { create(:user, account: account, role: :administrator) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:other_agent) { create(:user, account: account, role: :agent) }
    let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }
    let(:custom_role_agent) { create(:user, account: account, role: :agent) }
    let(:ownerless_response) { account.canned_responses.find_by!(short_code: 'name-short-code') }
    let!(:agent_response) { create(:canned_response, account: account, created_by: agent) }
    let!(:other_agent_response) { create(:canned_response, account: account, created_by: other_agent) }
    let!(:custom_role_agent_response) { create(:canned_response, account: account, created_by: custom_role_agent) }

    before do
      custom_role_agent.account_users.find_by!(account: account).update!(custom_role: custom_role)
    end

    describe 'GET index' do
      it 'lists every canned response of the account for an administrator' do
        get "/api/v1/accounts/#{account.id}/canned_responses", headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to contain_exactly(
          ownerless_response.id, agent_response.id, other_agent_response.id, custom_role_agent_response.id
        )
      end

      it 'lists every canned response of the account for an agent, including the ones owned by others' do
        get "/api/v1/accounts/#{account.id}/canned_responses", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to contain_exactly(
          ownerless_response.id, agent_response.id, other_agent_response.id, custom_role_agent_response.id
        )
      end

      it 'lists every canned response of the account for an agent with a custom role' do
        get "/api/v1/accounts/#{account.id}/canned_responses", headers: custom_role_agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.pluck('id')).to contain_exactly(
          ownerless_response.id, agent_response.id, other_agent_response.id, custom_role_agent_response.id
        )
      end

      it 'does not list canned responses from another account' do
        foreign_response = create(:canned_response, account: create(:account), created_by: agent)

        get "/api/v1/accounts/#{account.id}/canned_responses", headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body.pluck('id')).not_to include(foreign_response.id)
      end

      it 'serializes every item with the owner id and available name, or null when there is no owner' do
        agent.update!(name: 'Agent Full Name', display_name: 'Agent Display')

        get "/api/v1/accounts/#{account.id}/canned_responses", headers: agent.create_new_auth_token, as: :json

        items = response.parsed_body.index_by { |item| item['id'] }
        expect(items.values.map(&:keys)).to all(
          match_array(%w[id short_code content account_id created_at updated_at created_by])
        )
        expect(items[agent_response.id]['created_by']).to eq('id' => agent.id, 'name' => 'Agent Display')
        expect(items[other_agent_response.id]['created_by']).to eq('id' => other_agent.id, 'name' => other_agent.available_name)
        expect(items[ownerless_response.id]['created_by']).to be_nil
        expect(items[agent_response.id]).to include('short_code' => agent_response.short_code, 'content' => agent_response.content,
                                                    'account_id' => account.id)
      end

      it 'falls back to the user name when the owner has no display name' do
        agent.update!(name: 'Agent Full Name', display_name: nil)

        get "/api/v1/accounts/#{account.id}/canned_responses", headers: agent.create_new_auth_token, as: :json

        item = response.parsed_body.find { |entry| entry['id'] == agent_response.id }
        expect(item['created_by']).to eq('id' => agent.id, 'name' => 'Agent Full Name')
      end

      it 'loads the owners without one query per canned response' do
        headers = administrator.create_new_auth_token
        user_queries = []
        counter = lambda do |_name, _started, _finished, _unique_id, payload|
          user_queries << payload[:sql] if payload[:sql].match?(/\ASELECT .*FROM "users"/m) && !payload[:cached]
        end

        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/canned_responses", headers: headers, as: :json
        end
        baseline = user_queries.size

        create_list(:user, 3, account: account).each { |owner| create(:canned_response, account: account, created_by: owner) }
        user_queries.clear

        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          get "/api/v1/accounts/#{account.id}/canned_responses", headers: headers, as: :json
        end

        expect(response.parsed_body.size).to eq(7)
        expect(user_queries.size).to eq(baseline)
      end
    end

    describe 'POST create' do
      it 'allows an administrator and makes them the owner' do
        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: { short_code: 'admin-new', content: 'content' }, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.find_by!(short_code: 'admin-new').created_by).to eq(administrator)
        expect(response.parsed_body['created_by']).to eq('id' => administrator.id, 'name' => administrator.available_name)
      end

      it 'allows an agent without a custom role and returns the serialized canned response' do
        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: { short_code: 'agent-new', content: 'agent content' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        created = account.canned_responses.find_by!(short_code: 'agent-new')
        expect(created.created_by).to eq(agent)
        expect(response.parsed_body).to include(
          'id' => created.id, 'short_code' => 'agent-new', 'content' => 'agent content', 'account_id' => account.id,
          'created_by' => { 'id' => agent.id, 'name' => agent.available_name }
        )
      end

      it 'ignores a created_by_id sent by the client' do
        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: { short_code: 'spoofed', content: 'content', created_by_id: other_agent.id,
                       canned_response: { short_code: 'spoofed', content: 'content', created_by_id: other_agent.id } },
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.canned_responses.find_by!(short_code: 'spoofed').created_by_id).to eq(agent.id)
        expect(response.parsed_body['created_by']['id']).to eq(agent.id)
      end

      it 'rejects an agent with a custom role' do
        expect do
          post "/api/v1/accounts/#{account.id}/canned_responses",
               params: { short_code: 'custom-new', content: 'content' }, headers: custom_role_agent.create_new_auth_token, as: :json
        end.not_to change(CannedResponse, :count)

        expect(response).to have_http_status(:unauthorized)
      end

      it 'allows an administrator that also has a custom role' do
        administrator.account_users.find_by!(account: account).update!(custom_role: custom_role)

        post "/api/v1/accounts/#{account.id}/canned_responses",
             params: { short_code: 'admin-custom-new', content: 'content' }, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end

    describe 'PUT update' do
      it 'lets an administrator update their own, other users and ownerless canned responses' do
        [agent_response, other_agent_response, ownerless_response].each do |canned_response|
          put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
              params: { content: "admin edit #{canned_response.id}" }, headers: administrator.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(canned_response.reload.content).to eq("admin edit #{canned_response.id}")
        end
      end

      it 'lets an administrator update a canned response they own' do
        admin_response = create(:canned_response, account: account, created_by: administrator)

        put "/api/v1/accounts/#{account.id}/canned_responses/#{admin_response.id}",
            params: { content: 'admin own edit' }, headers: administrator.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(admin_response.reload.content).to eq('admin own edit')
      end

      it 'lets an agent update their own canned response and keeps them as owner' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{agent_response.id}",
            params: { short_code: 'renamed', content: 'edited' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(agent_response.reload).to have_attributes(short_code: 'renamed', content: 'edited', created_by_id: agent.id)
        expect(response.parsed_body).to include(
          'id' => agent_response.id, 'short_code' => 'renamed', 'content' => 'edited',
          'created_by' => { 'id' => agent.id, 'name' => agent.available_name }
        )
      end

      it 'returns created_by as null when an administrator updates an ownerless canned response' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{ownerless_response.id}",
            params: { content: 'edited' }, headers: administrator.create_new_auth_token, as: :json

        expect(response.parsed_body).to include('id' => ownerless_response.id, 'created_by' => nil)
      end

      it 'does not let an agent change the owner through params' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{agent_response.id}",
            params: { content: 'edited', created_by_id: other_agent.id, canned_response: { content: 'edited', created_by_id: other_agent.id } },
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(agent_response.reload.created_by_id).to eq(agent.id)
      end

      it 'rejects an agent updating a canned response owned by someone else' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{other_agent_response.id}",
            params: { content: 'hijack' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(other_agent_response.reload.content).not_to eq('hijack')
      end

      it 'rejects an agent updating an ownerless canned response' do
        put "/api/v1/accounts/#{account.id}/canned_responses/#{ownerless_response.id}",
            params: { content: 'hijack' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ownerless_response.reload.content).not_to eq('hijack')
      end

      it 'rejects an agent with a custom role for own, other and ownerless canned responses' do
        [custom_role_agent_response, agent_response, ownerless_response].each do |canned_response|
          put "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
              params: { content: 'custom edit' }, headers: custom_role_agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unauthorized)
          expect(canned_response.reload.content).not_to eq('custom edit')
        end
      end

      it 'returns not found for a canned response of another account' do
        foreign_response = create(:canned_response, account: create(:account), created_by: agent)

        put "/api/v1/accounts/#{account.id}/canned_responses/#{foreign_response.id}",
            params: { content: 'cross account' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(foreign_response.reload.content).not_to eq('cross account')
      end
    end

    describe 'DELETE destroy' do
      it 'lets an administrator delete their own, other users and ownerless canned responses' do
        admin_response = create(:canned_response, account: account, created_by: administrator)

        [admin_response, agent_response, ownerless_response].each do |canned_response|
          delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
                 headers: administrator.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(CannedResponse.exists?(canned_response.id)).to be(false)
        end
      end

      it 'lets an agent delete their own canned response' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{agent_response.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(CannedResponse.exists?(agent_response.id)).to be(false)
      end

      it 'rejects an agent deleting a canned response owned by someone else' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{other_agent_response.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(CannedResponse.exists?(other_agent_response.id)).to be(true)
      end

      it 'rejects an agent deleting an ownerless canned response' do
        delete "/api/v1/accounts/#{account.id}/canned_responses/#{ownerless_response.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(CannedResponse.exists?(ownerless_response.id)).to be(true)
      end

      it 'rejects an agent with a custom role for own, other and ownerless canned responses' do
        [custom_role_agent_response, agent_response, ownerless_response].each do |canned_response|
          delete "/api/v1/accounts/#{account.id}/canned_responses/#{canned_response.id}",
                 headers: custom_role_agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unauthorized)
          expect(CannedResponse.exists?(canned_response.id)).to be(true)
        end
      end

      it 'returns not found for a canned response of another account' do
        foreign_response = create(:canned_response, account: create(:account), created_by: agent)

        delete "/api/v1/accounts/#{account.id}/canned_responses/#{foreign_response.id}",
               headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:not_found)
        expect(CannedResponse.exists?(foreign_response.id)).to be(true)
      end
    end
  end
end
