# Twilio voice webhooks. Unauthenticated by design (Twilio calls them);
# every request is validated against the channel resolved from the :phone
# path segment plus the posted AccountSid.
class Twilio::VoiceController < ApplicationController
  before_action :set_channel

  # Returns TwiML. Three legs land here:
  # 1. agent browser leg (TwiML app, is_agent=true, To=<conference name>)
  # 2. outbound contact leg (calls.create url, Call row already exists)
  # 3. inbound contact leg (number's voice_url, Call row gets created)
  def call_twiml
    return render_agent_leg if params[:is_agent] == 'true'

    call = Call.find_by(provider: :twilio, provider_call_id: params[:CallSid])
    return render_contact_leg(call) if call.present?

    render_inbound_leg
  end

  def status
    call = Call.find_by(provider: :twilio, provider_call_id: params[:CallSid])
    return head :ok if call.blank?

    mapped = map_call_status(call, params[:CallStatus])
    call.apply_status!(mapped) if mapped.present?
    head :ok
  end

  def conference_status
    call = Voice::TwilioConferenceService.find_call_by_conference_name(params[:FriendlyName])
    return head :ok if call.blank?

    case params[:StatusCallbackEvent]
    when 'conference-start'
      call.update!(meta: call.meta.merge('conference_sid' => params[:ConferenceSid]))
    when 'conference-end'
      call.apply_status!(call.status == Call::STATUS_IN_PROGRESS ? 'completed' : 'no-answer')
    end
    head :ok
  end

  def recording_status
    return head :ok unless params[:RecordingStatus] == 'completed'

    call = Call.where(provider: :twilio).where("meta->>'conference_sid' = ?", params[:ConferenceSid]).first
    return head :ok if call.blank?

    Voice::RecordingAttachmentJob.perform_later(call.id, params[:RecordingUrl])
    head :ok
  end

  private

  def set_channel
    @channel = Channel::TwilioSms.find_by!(phone_number: params[:phone])
    # cheap authenticity check: the posted AccountSid must match the channel
    head :unauthorized if params[:AccountSid].present? && params[:AccountSid] != @channel.account_sid
  end

  def render_agent_leg
    call = Voice::TwilioConferenceService.find_call_by_conference_name(params[:To])
    return render_reject if call.blank? || call.terminal?

    render_conference(call, start_on_enter: true, end_on_exit: true)
  end

  def render_contact_leg(call)
    return render_reject if call.terminal?

    # Outbound: the contact answered the dialed leg — mark and bridge them in.
    call.apply_status!(Call::STATUS_IN_PROGRESS) if call.outgoing?
    render_conference(call, start_on_enter: call.outgoing?, end_on_exit: true)
  end

  def render_inbound_leg
    return render_reject unless @channel.voice_enabled? && @channel.inbound_calls_enabled?

    call = Voice::InboundCallBuilder.new(
      inbox: @channel.inbox,
      provider: :twilio,
      provider_call_id: params[:CallSid],
      caller_phone: normalized_caller(params[:From]),
      caller_name: params[:CallerName]
    ).perform
    return render_reject if call.blank?

    # Contact waits (hold music) until the agent's leg starts the conference.
    render_conference(call, start_on_enter: false, end_on_exit: true)
  end

  def render_conference(call, start_on_enter:, end_on_exit:)
    name = Voice::TwilioConferenceService.conference_name(call)
    response = Twilio::TwiML::VoiceResponse.new do |r|
      r.dial do |dial|
        dial.conference(
          name,
          beep: false,
          start_conference_on_enter: start_on_enter,
          end_conference_on_exit: end_on_exit,
          record: 'record-from-start',
          recording_status_callback: @channel.voice_recording_status_webhook_url,
          status_callback: @channel.voice_conference_status_webhook_url,
          status_callback_event: 'start end join leave'
        )
      end
    end
    render xml: response.to_s
  end

  def render_reject
    response = Twilio::TwiML::VoiceResponse.new(&:reject)
    render xml: response.to_s
  end

  # Calls arriving over SIP trunks/domains carry a SIP URI in From
  # ("sip:+5411xxxx@gw.example.com:5060"). Reduce it to the user part so
  # contact identity stays consistent with PSTN callers.
  def normalized_caller(from)
    return from unless from.to_s.start_with?('sip:', 'sips:')

    from.sub(/\Asips?:/, '').split('@').first.split(';').first
  end

  TERMINAL_STATUS_MAP = { 'busy' => 'busy', 'no-answer' => 'no-answer', 'failed' => 'failed', 'canceled' => 'canceled' }.freeze

  # Twilio CallStatus → internal status. Returns nil for states we ignore.
  def map_call_status(call, twilio_status)
    return Call::STATUS_IN_PROGRESS if twilio_status == 'in-progress'
    return call.status == Call::STATUS_IN_PROGRESS ? 'completed' : 'no-answer' if twilio_status == 'completed'

    TERMINAL_STATUS_MAP[twilio_status]
  end
end
