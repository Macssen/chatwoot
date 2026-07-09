class Contacts::PermissionFilterService
  attr_reader :contacts, :user, :account

  def initialize(contacts, user, account)
    @contacts = contacts
    @user = user
    @account = account
  end

  def perform
    return contacts unless restricted_by_custom_role?
    return contacts if permissions.include?('contact_manage')

    contacts_from_visible_conversations
  end

  private

  def restricted_by_custom_role?
    account_user.present? && account_user.role == 'agent' && account_user.custom_role_id.present?
  end

  def contacts_from_visible_conversations
    if permissions.include?('conversation_manage')
      contacts_with_conversations
    elsif permissions.include?('conversation_unassigned_manage')
      contacts_with_conversations(assignee_id: [nil, user.id])
    elsif permissions.include?('conversation_participating_manage')
      contacts_with_conversations(assignee_id: user.id)
    else
      contacts.none
    end
  end

  # Correlated EXISTS instead of a JOIN: a JOIN + DISTINCT breaks the Sift
  # sort scopes (they select columns outside the DISTINCT) and duplicates
  # rows against pagination.
  def contacts_with_conversations(assignee_clause = nil)
    conversations = Conversation.where('conversations.contact_id = contacts.id')
                                .where(account_id: account.id, inbox_id: user_inbox_ids)
    conversations = conversations.where(assignee_clause) if assignee_clause
    contacts.where(conversations.arel.exists)
  end

  def user_inbox_ids
    user.inboxes.where(account_id: account.id).select(:id)
  end

  def account_user
    @account_user ||= AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def permissions
    account_user.custom_role.permissions
  end
end
