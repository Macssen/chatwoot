# Reverses VoiceWebhookSetupService: removes the TwiML app and detaches the
# number's voice webhooks. Best-effort — a Twilio outage must not trap admins
# with a channel they can't disable.
class Twilio::VoiceTeardownService
  pattr_initialize [:channel!]

  def perform
    remove_twiml_app
    unwire_phone_number
  rescue StandardError => e
    Rails.logger.warn("[TWILIO VOICE] teardown for #{channel.phone_number} failed: #{e.message}")
  end

  private

  def client
    @client ||= channel.client
  end

  def remove_twiml_app
    return if channel.twiml_app_sid.blank?

    client.applications(channel.twiml_app_sid).delete
    channel.update_column(:twiml_app_sid, nil) # rubocop:disable Rails/SkipsModelValidations
  end

  def unwire_phone_number
    number = client.incoming_phone_numbers.list(phone_number: channel.phone_number).first
    return if number.blank?

    client.incoming_phone_numbers(number.sid).update(voice_url: '', status_callback: '')
  end
end
