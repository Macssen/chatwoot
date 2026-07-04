# Conference-model orchestration for Twilio calls. Every call gets a named
# conference; the contact's phone leg and the agent's browser leg both dial
# into it. The name doubles as the routing key between REST actions, TwiML
# generation and conference status webhooks.
class Voice::TwilioConferenceService
  NAME_PATTERN = /\Aconf_acct(?<account_id>\d+)_call(?<call_id>\d+)\z/

  pattr_initialize [:call!]

  def self.conference_name(call)
    "conf_acct#{call.account_id}_call#{call.id}"
  end

  def self.find_call_by_conference_name(name)
    match = NAME_PATTERN.match(name.to_s)
    return if match.blank?

    Call.find_by(id: match[:call_id], account_id: match[:account_id])
  end

  def conference_name
    self.class.conference_name(call)
  end

  # Reserves the call for one agent. Raises 409 when another agent won the race.
  def claim_agent!(user)
    call.with_lock do
      if call.accepted_by_agent_id.present? && call.accepted_by_agent_id != user.id
        raise CustomExceptions::CallAlreadyAccepted.new(agent_name: call.accepted_by_agent&.available_name)
      end
      raise Voice::CallErrors::CallFailed, 'call already ended' if call.terminal?

      call.update!(accepted_by_agent_id: user.id)
    end
    call.apply_status!(Call::STATUS_IN_PROGRESS)
  end

  # Agent leaves or declines. Ringing incoming call → reject; live call → complete.
  def leave!
    if call.status == Call::STATUS_RINGING && call.incoming?
      hangup_contact_leg
      call.apply_status!('rejected', end_reason: 'agent_rejected')
    else
      end_conference
      call.apply_status!(call.status == Call::STATUS_IN_PROGRESS ? 'completed' : 'canceled')
    end
  end

  def hangup_contact_leg
    client.calls(call.provider_call_id).update(status: 'completed')
  rescue Twilio::REST::RestError => e
    Rails.logger.warn("[TWILIO VOICE] hangup of #{call.provider_call_id} failed: #{e.message}")
  end

  def end_conference
    client.conferences.list(friendly_name: conference_name, status: 'in-progress').each do |conference|
      client.conferences(conference.sid).update(status: 'completed')
    end
  rescue Twilio::REST::RestError => e
    Rails.logger.warn("[TWILIO VOICE] ending conference #{conference_name} failed: #{e.message}")
  end

  private

  def client
    @client ||= call.inbox.channel.client
  end
end
