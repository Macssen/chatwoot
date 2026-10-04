# Shared by the pre-sale (questions) and post-sale (order messages) importers.
# A MercadoLibre buyer maps to a single Chatwoot contact across both inboxes through the contact identifier.
module Mercadolibre::ConversationHelpers
  private

  def contact_inbox_for(buyer_id)
    existing = channel.inbox.contact_inboxes.find_by(source_id: buyer_id.to_s)
    return existing if existing

    nickname = buyer_nickname(buyer_id)
    ::ContactInboxWithContactBuilder.new(
      source_id: buyer_id.to_s,
      inbox: channel.inbox,
      contact_attributes: {
        name: nickname.presence || "MercadoLibre #{buyer_id}",
        identifier: "mercadolibre:#{buyer_id}",
        additional_attributes: { social_profiles: { mercadolibre: nickname }, mercadolibre_user_id: buyer_id }
      }
    ).perform
  end

  # Finds the open conversation tied to the given MercadoLibre reference (item_id or pack_id), or starts a new one.
  # The block returns extra additional_attributes and only runs when a conversation is created.
  def find_or_create_conversation(contact_inbox, key, value)
    scope = contact_inbox.conversations.where("conversations.additional_attributes->>'#{key}' = ?", value.to_s).order(created_at: :desc)
    conversation = channel.inbox.lock_to_single_conversation ? scope.first : scope.where.not(status: :resolved).first
    conversation || ::Conversation.create!(
      account_id: channel.account_id,
      inbox_id: channel.inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: (block_given? ? yield : {}).merge(key => value.to_s)
    )
  end

  def message_exists?(source_id)
    channel.inbox.messages.exists?(source_id: source_id)
  end

  def buyer_nickname(buyer_id)
    channel.client.user(buyer_id)['nickname']
  rescue Mercadolibre::Client::ApiError
    nil
  end
end
