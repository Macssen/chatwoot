require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:conversation) { create(:conversation, account: account) }

  permissions :destroy? do
    context 'when user is an administrator' do
      it 'allows destroy' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when user is an agent' do
      it 'denies destroy' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end
  end

  permissions :index? do
    context 'when user is authenticated' do
      it 'allows index' do
        expect(subject).to permit(agent_context, conversation)
      end
    end
  end

  permissions :show? do
    context 'when user is an administrator' do
      it 'allows access' do
        expect(subject).to permit(administrator_context, conversation)
      end
    end

    context 'when agent has inbox access' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'allows access' do
        expect(subject).to permit(agent_context, conversation)
      end
    end

    context 'when agent has team access' do
      let(:team) { create(:team, account: account) }
      let(:conversation) { create(:conversation, :with_team, account: account, team: team) }

      before { create(:team_member, team: team, user: agent) }

      it 'allows access' do
        expect(subject).to permit(agent_context, conversation)
      end
    end

    context 'when agent lacks inbox and team access' do
      let(:conversation) { create(:conversation, account: account) }

      it 'denies access' do
        expect(subject).not_to permit(agent_context, conversation)
      end
    end

    context 'when agent has a custom role' do
      let(:inbox) { create(:inbox, account: account) }
      let(:custom_role) { create(:custom_role, account: account, permissions: permissions) }

      before do
        create(:inbox_member, user: agent, inbox: inbox)
        agent.account_users.find_by(account: account).update!(custom_role: custom_role)
      end

      context 'with conversation_manage' do
        let(:permissions) { ['conversation_manage'] }
        let(:conversation) { create(:conversation, account: account, inbox: inbox) }

        it 'allows access to any conversation in the inbox' do
          expect(subject).to permit(agent_context, conversation)
        end
      end

      context 'with conversation_unassigned_manage' do
        let(:permissions) { ['conversation_unassigned_manage'] }

        it 'allows access to unassigned conversations' do
          conversation = create(:conversation, account: account, inbox: inbox)
          expect(subject).to permit(agent_context, conversation)
        end

        it 'allows access to own conversations' do
          conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)
          expect(subject).to permit(agent_context, conversation)
        end

        it 'denies access to conversations assigned to others' do
          other_agent = create(:user, account: account, role: :agent)
          conversation = create(:conversation, account: account, inbox: inbox, assignee: other_agent)
          expect(subject).not_to permit(agent_context, conversation)
        end
      end

      context 'with conversation_participating_manage' do
        let(:permissions) { ['conversation_participating_manage'] }

        it 'allows access to own conversations' do
          conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)
          expect(subject).to permit(agent_context, conversation)
        end

        it 'allows access to conversations the agent participates in' do
          conversation = create(:conversation, account: account, inbox: inbox)
          create(:conversation_participant, conversation: conversation, user: agent)
          expect(subject).to permit(agent_context, conversation)
        end

        it 'denies access to unassigned conversations' do
          conversation = create(:conversation, account: account, inbox: inbox)
          expect(subject).not_to permit(agent_context, conversation)
        end
      end

      context 'without conversation permissions' do
        let(:permissions) { ['contact_manage'] }
        let(:conversation) { create(:conversation, account: account, inbox: inbox) }

        it 'denies access' do
          expect(subject).not_to permit(agent_context, conversation)
        end
      end
    end
  end
end
