# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CannedResponsePolicy, type: :policy do
  subject(:canned_response_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:custom_role_agent) { create(:user, account: account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account_id: account.id) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: agent.account_users.find_by(account_id: account.id) }
  end
  let(:custom_role_agent_context) do
    account_user = custom_role_agent.account_users.find_by(account_id: account.id)
    account_user.update!(custom_role: custom_role)
    { user: custom_role_agent, account: account, account_user: account_user }
  end

  let(:agent_response) { create(:canned_response, account: account, created_by: agent) }
  let(:other_agent_response) { create(:canned_response, account: account, created_by: other_agent) }
  let(:custom_role_agent_response) { create(:canned_response, account: account, created_by: custom_role_agent) }
  let(:ownerless_response) { create(:canned_response, account: account) }

  permissions :index? do
    context 'when administrator' do
      it { expect(canned_response_policy).to permit(administrator_context, CannedResponse) }
    end

    context 'when agent without a custom role' do
      it { expect(canned_response_policy).to permit(agent_context, CannedResponse) }
    end

    context 'when agent with a custom role' do
      it { expect(canned_response_policy).to permit(custom_role_agent_context, CannedResponse) }
    end
  end

  permissions :create? do
    context 'when administrator' do
      it { expect(canned_response_policy).to permit(administrator_context, CannedResponse) }

      it 'permits an administrator that also has a custom role' do
        administrator_context[:account_user].update!(custom_role: custom_role)

        expect(canned_response_policy).to permit(administrator_context, CannedResponse)
      end
    end

    context 'when agent without a custom role' do
      it { expect(canned_response_policy).to permit(agent_context, CannedResponse) }
    end

    context 'when agent with a custom role' do
      it { expect(canned_response_policy).not_to permit(custom_role_agent_context, CannedResponse) }
    end
  end

  permissions :update?, :destroy? do
    context 'when administrator' do
      it { expect(canned_response_policy).to permit(administrator_context, agent_response) }
      it { expect(canned_response_policy).to permit(administrator_context, ownerless_response) }
      it { expect(canned_response_policy).to permit(administrator_context, create(:canned_response, account: account, created_by: administrator)) }
    end

    context 'when agent without a custom role' do
      it { expect(canned_response_policy).to permit(agent_context, agent_response) }
      it { expect(canned_response_policy).not_to permit(agent_context, other_agent_response) }
      it { expect(canned_response_policy).not_to permit(agent_context, ownerless_response) }
    end

    context 'when agent with a custom role' do
      it { expect(canned_response_policy).not_to permit(custom_role_agent_context, custom_role_agent_response) }
      it { expect(canned_response_policy).not_to permit(custom_role_agent_context, agent_response) }
      it { expect(canned_response_policy).not_to permit(custom_role_agent_context, ownerless_response) }
    end
  end
end
