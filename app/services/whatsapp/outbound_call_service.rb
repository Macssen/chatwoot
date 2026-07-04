# Places a business-initiated WhatsApp call for an agent. When the contact
# hasn't granted call permission, falls back to sending Meta's
# call-permission-request interactive message (throttled per contact inbox)
# and reports which of the two permission states applies.
class Whatsapp::OutboundCallService
  PERMISSION_THROTTLE_TTL = 5.minutes

  pattr_initialize [:conversation!, :user!, :sdp_offer!]

  Result = Struct.new(:call, :permission_status, keyword_init: true)

  def perform
    raise Voice::CallErrors::CallFailed, 'voice calling is not enabled on this inbox' unless channel.try(:voice_enabled?)

    provider_call_id = provider_service.initiate_call(to: recipient, sdp_offer: sdp_offer)
    raise Voice::CallErrors::CallFailed, 'provider did not return a call id' if provider_call_id.blank?

    call = Voice::OutboundCallBuilder.new(
      conversation: conversation,
      agent: user,
      provider: :whatsapp,
      provider_call_id: provider_call_id,
      sdp_offer: sdp_offer
    ).perform
    Result.new(call: call)
  rescue Voice::CallErrors::NoCallPermission
    Result.new(permission_status: request_permission)
  end

  private

  def channel
    @channel ||= conversation.inbox.channel
  end

  def provider_service
    @provider_service ||= channel.provider_service
  end

  # Meta identifies WhatsApp users by wa_id, which is what the contact inbox
  # stores as source_id.
  def recipient
    conversation.contact_inbox.source_id
  end

  def request_permission
    key = format(::Redis::Alfred::WHATSAPP_CALL_PERMISSION_THROTTLE, contact_inbox_id: conversation.contact_inbox_id)
    return 'permission_pending' if ::Redis::Alfred.get(key).present?

    provider_service.send_call_permission_request(recipient, permission_request_body)
    ::Redis::Alfred.setex(key, '1', PERMISSION_THROTTLE_TTL)
    'permission_requested'
  end

  def permission_request_body
    channel.provider_config['call_permission_request_body'].presence ||
      I18n.t('conversations.messages.whatsapp.call_permission_request_body')
  end
end
