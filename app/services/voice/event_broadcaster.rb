# Pushes voice_call.* events to agent dashboards over ActionCable.
# Recipient policy: the conversation assignee when present, otherwise every
# member of the inbox plus account administrators — the dashboard itself
# suppresses ringing for agents who are not online.
class Voice::EventBroadcaster
  pattr_initialize [:call!]

  def broadcast(event_name, payload)
    tokens = recipient_tokens
    return if tokens.blank?

    ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, payload.merge(account_id: call.account_id))
  end

  def incoming_payload
    base_payload.merge(
      sdp_offer: call.sdp_offer,
      ice_servers: call.ice_servers.presence || Call.default_ice_servers,
      caller: caller_payload
    )
  end

  def base_payload
    {
      id: call.id,
      call_id: call.provider_call_id,
      provider: call.provider,
      conversation_id: call.conversation.display_id,
      inbox_id: call.inbox_id
    }
  end

  private

  def caller_payload
    contact = call.contact
    {
      name: contact.name,
      phone: contact.phone_number,
      avatar: contact.avatar_url,
      additionalAttributes: contact.additional_attributes
    }
  end

  def recipient_tokens
    assignee = call.conversation.assignee
    return [assignee.pubsub_token] if assignee.present?

    agents = call.inbox.members.to_a + call.account.administrators.to_a
    agents.uniq.filter_map(&:pubsub_token)
  end
end
