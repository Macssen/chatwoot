# Processes Meta "calls"-field webhooks for a WhatsApp Cloud inbox.
#
# Event shapes handled (value hash, symbol keys):
#   calls: [{ id:, from:, to:, event: 'connect'|'terminate', direction:,
#             session: { sdp_type:, sdp: }, status:, duration: }]
#   statuses: [{ id:, status: 'RINGING'|'ACCEPTED'|'REJECTED'|..., recipient_id: }]
#   contacts: [{ wa_id:, profile: { name: } }]
#
# Ordering hazards covered: a `terminate` can overtake its `connect` (tombstone
# via Redis), and duplicate webhooks are absorbed by the unique
# [provider, provider_call_id] index through Voice::InboundCallBuilder.
class Whatsapp::IncomingCallService
  pattr_initialize [:inbox!, :value!]

  def perform
    return handle_statuses if value[:statuses].present?

    call_payload = value.dig(:calls, 0)
    return if call_payload.blank?

    case call_payload[:event]
    when 'connect'
      handle_connect(call_payload)
    when 'terminate'
      handle_terminate(call_payload)
    else
      Rails.logger.info("[WHATSAPP CALL] unhandled call event #{call_payload[:event]} for #{call_payload[:id]}")
    end
  end

  private

  def channel
    @channel ||= inbox.channel
  end

  def handle_connect(payload)
    if payload[:direction].to_s.casecmp('BUSINESS_INITIATED').zero?
      handle_outbound_connect(payload)
    else
      handle_inbound_offer(payload)
    end
  end

  # Inbound caller: Meta delivers the WebRTC SDP offer. Reject at the provider
  # when calling/inbound is off; otherwise materialize the call and ring agents.
  def handle_inbound_offer(payload)
    return reject_at_provider(payload[:id]) unless channel.voice_enabled? && channel.inbound_calls_enabled?

    call = Voice::InboundCallBuilder.new(
      inbox: inbox,
      provider: :whatsapp,
      provider_call_id: payload[:id],
      caller_phone: payload[:from],
      caller_name: caller_name,
      source_id: payload[:from],
      sdp_offer: payload.dig(:session, :sdp)
    ).perform
    return if call.blank?

    return finalize_tombstoned(call) if consume_terminate_tombstone(payload[:id])

    broadcaster = Voice::EventBroadcaster.new(call: call)
    broadcaster.broadcast('voice_call.incoming', broadcaster.incoming_payload)
  end

  # For business-initiated calls, `connect` carries Meta's SDP answer —
  # the agent's browser applies it to complete the WebRTC handshake.
  def handle_outbound_connect(payload)
    call = find_call(payload[:id])
    return if call.blank?

    sdp_answer = payload.dig(:session, :sdp)
    call.update!(meta: call.meta.merge('sdp_answer' => sdp_answer))

    broadcaster = Voice::EventBroadcaster.new(call: call)
    broadcaster.broadcast('voice_call.outbound_connected', broadcaster.base_payload.merge(sdp_answer: sdp_answer))
  end

  def handle_terminate(payload)
    call = find_call(payload[:id])
    if call.blank?
      # connect hasn't been processed yet — leave a tombstone so it can finalize
      ::Redis::Alfred.setex(tombstone_key(payload[:id]), '1', 10.minutes)
      return
    end

    call.duration_seconds = payload[:duration].to_i if payload[:duration].present?
    call.apply_status!(terminate_status_for(call, payload))

    broadcaster = Voice::EventBroadcaster.new(call: call)
    broadcaster.broadcast('voice_call.ended', broadcaster.base_payload)
  end

  def handle_statuses
    status = value.dig(:statuses, 0)
    call = find_call(status[:id])
    return if call.blank?

    case status[:status].to_s.upcase
    when 'ACCEPTED'
      call.apply_status!(Call::STATUS_IN_PROGRESS)
      broadcaster = Voice::EventBroadcaster.new(call: call)
      broadcaster.broadcast('voice_call.outbound_accepted', broadcaster.base_payload)
    when 'REJECTED'
      call.apply_status!('rejected')
      broadcaster = Voice::EventBroadcaster.new(call: call)
      broadcaster.broadcast('voice_call.ended', broadcaster.base_payload)
    end
    # RINGING and other intermediate states need no action — the call row
    # already starts at ringing.
  end

  def terminate_status_for(call, payload)
    return 'failed' if payload[:status].to_s.casecmp('FAILED').zero?
    return 'completed' if call.status == Call::STATUS_IN_PROGRESS

    # Never answered: the caller (or Meta) hung up while ringing.
    'no-answer'
  end

  def finalize_tombstoned(call)
    call.apply_status!('no-answer')
  end

  def consume_terminate_tombstone(provider_call_id)
    key = tombstone_key(provider_call_id)
    return false if ::Redis::Alfred.get(key).blank?

    ::Redis::Alfred.delete(key)
    true
  end

  def tombstone_key(provider_call_id)
    format(::Redis::Alfred::WHATSAPP_CALL_TERMINATE_TOMBSTONE, call_id: provider_call_id)
  end

  def reject_at_provider(provider_call_id)
    channel.provider_service.reject_call(call_id: provider_call_id)
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP CALL] reject of #{provider_call_id} failed: #{e.message}")
  end

  def find_call(provider_call_id)
    call = Call.find_by(provider: :whatsapp, provider_call_id: provider_call_id)
    Rails.logger.warn("[WHATSAPP CALL] no call record for #{provider_call_id}") if call.blank?
    call
  end

  def caller_name
    value.dig(:contacts, 0, :profile, :name)
  end
end
