# Agent-side operations on WhatsApp calls: answering, declining and hanging
# up an existing call, plus initiating outbound calls. Provider interaction
# goes through the channel's WhatsappCloudService; local state lives on Call.
class Whatsapp::CallService
  pattr_initialize [:call!, { user: nil }]

  # Forwards the browser's SDP answer to Meta. Row-locked so two agents
  # racing to answer resolve deterministically — the loser gets a 409.
  def accept(sdp_answer)
    call.with_lock do
      validate_acceptable!
      forward_answer_to_provider(sdp_answer)
      call.accepted_by_agent_id = user.id
      call.meta = call.meta.merge('sdp_answer' => sdp_answer)
      call.save!
    end
    call.apply_status!(Call::STATUS_IN_PROGRESS)
  end

  def reject
    return if call.terminal?

    safe_provider_call { provider_service.reject_call(call_id: call.provider_call_id) }
    call.apply_status!('rejected', end_reason: 'agent_rejected')
    broadcast_ended
  end

  def terminate
    return if call.terminal?

    safe_provider_call { provider_service.terminate_call(call_id: call.provider_call_id) }
    final_status = call.status == Call::STATUS_IN_PROGRESS ? 'completed' : 'canceled'
    call.apply_status!(final_status)
    broadcast_ended
  end

  private

  def validate_acceptable!
    raise CustomExceptions::CallAlreadyAccepted.new(agent_name: call.accepted_by_agent&.available_name) if accepted_by_someone_else?
    raise Voice::CallErrors::CallFailed, 'call already ended' if call.terminal?
  end

  def forward_answer_to_provider(sdp_answer)
    provider_service.pre_accept_call(call_id: call.provider_call_id, sdp_answer: sdp_answer)
    provider_service.accept_call(call_id: call.provider_call_id, sdp_answer: sdp_answer)
  end

  def accepted_by_someone_else?
    call.accepted_by_agent_id.present? && call.accepted_by_agent_id != user&.id
  end

  # Hangup must always settle local state — Meta already knowing the call is
  # dead (or being unreachable) is not a reason to leave a call stuck open.
  def safe_provider_call
    yield
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP CALL] provider call action failed for #{call.provider_call_id}: #{e.message}")
  end

  def broadcast_ended
    broadcaster = Voice::EventBroadcaster.new(call: call)
    broadcaster.broadcast('voice_call.ended', broadcaster.base_payload)
  end

  def provider_service
    @provider_service ||= call.inbox.channel.provider_service
  end
end
