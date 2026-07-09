require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent' do
      it 'returns all conversations with no further filtering' do
        inbox_ids = agent.inboxes.where(account_id: account.id).pluck(:id)

        # The base implementation returns all conversations
        # expecting the caller to filter by assigned inboxes
        result = described_class.new(
          account.conversations.where(inbox_id: inbox_ids),
          agent,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent with a custom role' do
      let(:another_agent) { create(:user, account: account, role: :agent) }

      # Assignees must be inbox members; otherwise saving the conversation
      # triggers legacy round-robin auto-assignment.
      before { create(:inbox_member, user: another_agent, inbox: inbox) }

      let!(:assigned_conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
      let!(:other_assigned_conversation) { create(:conversation, account: account, inbox: inbox, assignee: another_agent) }
      let(:custom_role) { create(:custom_role, account: account, permissions: permissions) }
      let(:result) { described_class.new(account.conversations, agent, account).perform }

      before do
        agent.account_users.find_by(account_id: account.id).update!(custom_role: custom_role)
      end

      context 'with conversation_manage' do
        let(:permissions) { ['conversation_manage'] }

        it 'returns all accessible conversations' do
          expect(result).to contain_exactly(conversation, another_conversation, assigned_conversation, other_assigned_conversation)
        end

        it 'excludes conversations from inboxes the agent does not belong to' do
          other_inbox = create(:inbox, account: account)
          foreign_conversation = create(:conversation, account: account, inbox: other_inbox)

          expect(result).not_to include(foreign_conversation)
        end
      end

      context 'with conversation_unassigned_manage' do
        let(:permissions) { ['conversation_unassigned_manage'] }

        it 'returns unassigned and own conversations' do
          expect(result).to contain_exactly(conversation, another_conversation, assigned_conversation)
        end
      end

      context 'with conversation_participating_manage' do
        let(:permissions) { ['conversation_participating_manage'] }

        it 'returns only own conversations' do
          expect(result).to contain_exactly(assigned_conversation)
        end
      end

      context 'without conversation permissions' do
        let(:permissions) { ['contact_manage'] }

        it 'returns no conversations' do
          expect(result).to be_empty
        end
      end
    end
  end
end
