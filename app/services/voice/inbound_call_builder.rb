# Materializes an inbound call into Chatwoot records: contact (found or
# created from the caller id), conversation (reusing the inbox's conversation
# lock semantics), the Call row, and its voice_call message bubble.
# Idempotent on [provider, provider_call_id] so provider webhook retries
# return the existing call instead of raising.
class Voice::InboundCallBuilder
  pattr_initialize [:inbox!, :provider!, :provider_call_id!, :caller_phone!, { caller_name: nil, source_id: nil, sdp_offer: nil, ice_servers: nil }]

  def perform
    existing = Call.find_by(provider: provider, provider_call_id: provider_call_id)
    return existing if existing

    ActiveRecord::Base.transaction do
      set_contact
      set_conversation
      create_call
      create_message
    end
    @call
  rescue ActiveRecord::RecordNotUnique
    Call.find_by(provider: provider, provider_call_id: provider_call_id)
  end

  private

  def set_contact
    @contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: source_id || caller_phone,
      contact_attributes: { name: caller_name.presence || caller_phone, phone_number: normalized_phone }
    ).perform
  end

  def normalized_phone
    caller_phone.start_with?('+') ? caller_phone : "+#{caller_phone}"
  end

  def set_conversation
    existing = if inbox.lock_to_single_conversation
                 @contact_inbox.conversations.last
               else
                 @contact_inbox.conversations.where.not(status: :resolved).last
               end
    @conversation = existing || ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id
    )
  end

  def create_call
    @call = Call.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      conversation_id: @conversation.id,
      contact_id: @contact_inbox.contact_id,
      provider: provider,
      provider_call_id: provider_call_id,
      direction: :incoming,
      status: Call::STATUS_RINGING,
      meta: { 'sdp_offer' => sdp_offer, 'ice_servers' => ice_servers }.compact
    )
  end

  def create_message
    message = @conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      content_type: :voice_call,
      sender: @contact_inbox.contact,
      source_id: provider_call_id
    )
    @call.update!(message_id: message.id)
  end
end
