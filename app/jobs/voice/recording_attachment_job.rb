# Downloads a finished Twilio conference recording and attaches it to the
# call, then repaints the voice_call bubble so agents see the player.
class Voice::RecordingAttachmentJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: 30.seconds, attempts: 5

  def perform(call_id, recording_url)
    call = Call.find_by(id: call_id)
    return if call.blank? || call.recording.attached?

    username, password = call.inbox.channel.rest_credentials
    response = HTTParty.get("#{recording_url}.mp3", basic_auth: { username: username, password: password })
    raise "recording download failed with #{response.code}" unless response.success?

    call.recording.attach(
      io: StringIO.new(response.body),
      filename: "call-#{call.provider_call_id}.mp3",
      content_type: 'audio/mpeg'
    )

    message = call.message
    Rails.configuration.dispatcher.dispatch(Events::Types::MESSAGE_UPDATED, Time.zone.now, message: message.reload) if message.present?
  end
end
