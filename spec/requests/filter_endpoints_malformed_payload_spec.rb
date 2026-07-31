require 'rails_helper'

# The filter endpoints used to return HTTP 500 for any payload that did not match the documented
# shape, because FilterService assumed `payload` was an array of hashes and every `values` entry a
# string. `validate_payload` now rejects those upfront with 422. The specs also cover quote-heavy
# values, since the query builder interpolates attribute keys and query operators into the SQL
# string while values travel as bound parameters.
RSpec.describe 'Filter endpoints with malformed payloads', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }

  malformed_payloads = {
    'a missing payload' => {},
    'a payload that is not an array' => { payload: "' OR 1=1--" },
    'a payload holding strings instead of conditions' => { payload: ["' OR 1=1--"] },
    'a payload holding a bare condition instead of an array' => { payload: { attribute_key: 'status' } },
    'a query_operator that is not a string' => { payload: [{ attribute_key: 'created_at', filter_operator: 'is_present',
                                                             query_operator: { nested: 'object' } }] },
    'values holding an object' => { payload: [{ attribute_key: 'email', filter_operator: 'contains', values: [{ nested: 'object' }] }] },
    'values holding a nested array' => { payload: [{ attribute_key: 'email', filter_operator: 'contains', values: [['nested']] }] }
  }

  describe 'POST /api/v1/accounts/{account.id}/conversations/filter' do
    malformed_payloads.each do |description, payload|
      it "returns 422 for #{description}" do
        post "/api/v1/accounts/#{account.id}/conversations/filter", params: payload.to_json,
                                                                    headers: headers.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end
    end

    it 'accepts a scalar value and keeps filtering on it' do
      create(:conversation, account: account, status: :open)
      create(:conversation, account: account, status: :resolved)

      post "/api/v1/accounts/#{account.id}/conversations/filter",
           params: { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: 'open' }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['all_count']).to eq 1
    end

    it 'resolves the days_before operator instead of erroring' do
      create(:conversation, account: account, created_at: 10.days.ago)
      create(:conversation, account: account, created_at: 1.day.ago)

      post "/api/v1/accounts/#{account.id}/conversations/filter",
           params: { payload: [{ attribute_key: 'created_at', filter_operator: 'days_before', values: [7] }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['all_count']).to eq 1
    end

    it 'binds injected values instead of interpolating them into the query' do
      create(:conversation, account: account, status: :open)

      post "/api/v1/accounts/#{account.id}/conversations/filter",
           params: { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ["open' OR '1'='1"] }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['all_count']).to eq 0
    end

    it 'rejects an injected attribute_key' do
      post "/api/v1/accounts/#{account.id}/conversations/filter",
           params: { payload: [{ attribute_key: "status') OR 1=1--", filter_operator: 'equal_to', values: ['open'] }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects an injected query_operator' do
      post "/api/v1/accounts/#{account.id}/conversations/filter",
           params: { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'],
                                 query_operator: 'AND 1=1--' }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/contacts/filter' do
    malformed_payloads.each do |description, payload|
      it "returns 422 for #{description}" do
        post "/api/v1/accounts/#{account.id}/contacts/filter", params: payload.to_json,
                                                               headers: headers.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end
    end

    it 'accepts a scalar value and matches on the whole value, not its first character' do
      create(:contact, account: account, email: 'wanted@example.com')
      create(:contact, account: account, email: 'wilson@example.com')

      post "/api/v1/accounts/#{account.id}/contacts/filter",
           params: { payload: [{ attribute_key: 'email', filter_operator: 'equal_to', values: 'wanted@example.com' }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['count']).to eq 1
    end

    it 'binds injected values instead of interpolating them into the query' do
      create(:contact, account: account, email: 'wanted@example.com')

      post "/api/v1/accounts/#{account.id}/contacts/filter",
           params: { payload: [{ attribute_key: 'email', filter_operator: 'contains', values: ["a' OR 1=1--"] }] }.to_json,
           headers: headers.merge('CONTENT_TYPE' => 'application/json')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['meta']['count']).to eq 0
    end
  end
end
