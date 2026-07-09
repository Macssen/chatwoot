# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomRolePolicy, type: :policy do
  subject(:custom_role_policy) { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:custom_role) { create(:custom_role, account: account) }

  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account_id: account.id) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: agent.account_users.find_by(account_id: account.id) }
  end

  permissions :index?, :show?, :create?, :update?, :destroy? do
    context 'when administrator' do
      it { expect(custom_role_policy).to permit(administrator_context, custom_role) }
    end

    context 'when agent' do
      it { expect(custom_role_policy).not_to permit(agent_context, custom_role) }
    end
  end
end
