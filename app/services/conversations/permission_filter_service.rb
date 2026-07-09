class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'
    return filter_by_custom_role_permissions if custom_role_agent?

    accessible_conversations
  end

  private

  def accessible_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
  end

  def custom_role_agent?
    user_role == 'agent' && account_user&.custom_role_id.present?
  end

  def filter_by_custom_role_permissions
    permissions = account_user.permissions
    if permissions.include?('conversation_manage')
      accessible_conversations
    elsif permissions.include?('conversation_unassigned_manage')
      accessible_conversations.where(assignee_id: [nil, user.id])
    elsif permissions.include?('conversation_participating_manage')
      accessible_conversations.assigned_to(user)
    else
      conversations.none
    end
  end

  def account_user
    @account_user ||= AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
