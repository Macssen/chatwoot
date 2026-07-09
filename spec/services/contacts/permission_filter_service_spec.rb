require 'rails_helper'

RSpec.describe Contacts::PermissionFilterService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:another_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  let!(:my_contact) { create(:contact, account: account) }
  let!(:unassigned_contact) { create(:contact, account: account) }
  let!(:other_agent_contact) { create(:contact, account: account) }

  let(:result) { described_class.new(account.contacts, agent, account).perform }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: another_agent, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, contact: my_contact, assignee: agent)
    create(:conversation, account: account, inbox: inbox, contact: unassigned_contact)
    create(:conversation, account: account, inbox: inbox, contact: other_agent_contact, assignee: another_agent)
    # A contact whose only conversation lives in an inbox the agent does not belong to
    create(:conversation, account: account, inbox: other_inbox, contact: create(:contact, account: account))
  end

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all contacts' do
        expect(described_class.new(account.contacts, admin, account).perform).to match_array(account.contacts)
      end
    end

    context 'when user is an agent without a custom role' do
      it 'returns all contacts' do
        expect(result).to match_array(account.contacts)
      end
    end

    context 'when user is an agent with a custom role' do
      let(:custom_role) { create(:custom_role, account: account, permissions: permissions) }

      before do
        agent.account_users.find_by(account_id: account.id).update!(custom_role: custom_role)
      end

      context 'with contact_manage' do
        let(:permissions) { ['contact_manage'] }

        it 'returns all contacts' do
          expect(result).to match_array(account.contacts)
        end
      end

      context 'with conversation_manage' do
        let(:permissions) { ['conversation_manage'] }

        it 'returns contacts with conversations in the agent inboxes' do
          expect(result).to contain_exactly(my_contact, unassigned_contact, other_agent_contact)
        end
      end

      context 'with conversation_unassigned_manage' do
        let(:permissions) { ['conversation_unassigned_manage'] }

        it 'returns contacts from unassigned and own conversations' do
          expect(result).to contain_exactly(my_contact, unassigned_contact)
        end
      end

      context 'with conversation_participating_manage' do
        let(:permissions) { ['conversation_participating_manage'] }

        it 'returns only contacts from own conversations' do
          expect(result).to contain_exactly(my_contact)
        end
      end

      context 'without conversation or contact permissions' do
        let(:permissions) { ['report_manage'] }

        it 'returns no contacts' do
          expect(result).to be_empty
        end
      end
    end
  end
end
