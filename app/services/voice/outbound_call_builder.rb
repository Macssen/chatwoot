# Creates the Call row and outgoing voice_call message for an agent-initiated
# call on an existing conversation. The provider call must already exist —
# pass its id in provider_call_id.
class Voice::OutboundCallBuilder
  pattr_initialize [:conversation!, :agent!, :provider!, :provider_call_id!, { sdp_offer: nil }]

  def perform
    ActiveRecord::Base.transaction do
      create_call
      create_message
    end
    @call
  end

  private

  def create_call
    @call = Call.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      conversation_id: conversation.id,
      contact_id: conversation.contact_id,
      provider: provider,
      provider_call_id: provider_call_id,
      direction: :outgoing,
      status: Call::STATUS_RINGING,
      accepted_by_agent_id: agent.id,
      meta: { 'sdp_offer' => sdp_offer }.compact
    )
  end

  def create_message
    message = conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :voice_call,
      sender: agent,
      source_id: provider_call_id
    )
    @call.update!(message_id: message.id)
  end
end
