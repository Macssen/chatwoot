class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    return false unless administrator? || agent_bot? || agent_can_view_conversation?
    return true unless custom_role_agent?

    custom_role_allows_conversation?
  end

  private

  def agent_can_view_conversation?
    inbox_access? || team_access?
  end

  def custom_role_agent?
    account_user&.agent? && account_user.custom_role_id.present?
  end

  def custom_role_allows_conversation?
    permissions = account_user.custom_role.permissions
    if permissions.include?('conversation_manage')
      true
    elsif permissions.include?('conversation_unassigned_manage')
      record.assignee_id.nil? || assigned_to_user?
    elsif permissions.include?('conversation_participating_manage')
      assigned_to_user? || participant?
    else
      false
    end
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
