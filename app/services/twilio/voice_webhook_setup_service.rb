# Wires a Twilio number for voice: provisions a TwiML Application (used by the
# browser Voice SDK for agent legs) and points the incoming number's voice
# webhook at our call endpoint. Idempotent — reuses an existing TwiML app.
class Twilio::VoiceWebhookSetupService
  pattr_initialize [:channel!]

  def perform
    ensure_twiml_app
    wire_phone_number
  end

  private

  def client
    @client ||= channel.client
  end

  def ensure_twiml_app
    return if channel.twiml_app_sid.present?

    app = client.applications.create(
      friendly_name: "Chatwoot Voice #{channel.phone_number}",
      voice_url: channel.voice_call_webhook_url,
      voice_method: 'POST'
    )
    # update_column: we may be running inside the channel's own after_save.
    channel.update_column(:twiml_app_sid, app.sid) # rubocop:disable Rails/SkipsModelValidations
  end

  def wire_phone_number
    number = client.incoming_phone_numbers.list(phone_number: channel.phone_number).first
    raise Voice::CallErrors::CallFailed, "number #{channel.phone_number} not found in Twilio account" if number.blank?

    client.incoming_phone_numbers(number.sid).update(
      voice_url: channel.voice_call_webhook_url,
      voice_method: 'POST',
      status_callback: channel.voice_status_webhook_url,
      status_callback_method: 'POST'
    )
  end
end
