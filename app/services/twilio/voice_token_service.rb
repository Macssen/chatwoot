# Mints the JWT the browser Twilio Voice SDK Device authenticates with.
# Outgoing connects route through the channel's TwiML app (agent legs join
# conferences by name); direct incoming calls to the Device are not used.
class Twilio::VoiceTokenService
  TOKEN_TTL = 1.hour

  pattr_initialize [:channel!, :user!]

  def generate
    if channel.twiml_app_sid.blank? || channel.api_key_sid.blank?
      raise Voice::CallErrors::CallFailed, 'voice is not fully configured on this channel (missing TwiML app or API key)'
    end

    token = Twilio::JWT::AccessToken.new(
      channel.account_sid,
      channel.api_key_sid,
      channel.voice_api_secret,
      [voice_grant],
      identity: "agent-#{user.id}",
      ttl: TOKEN_TTL.to_i
    )
    token.to_jwt
  end

  private

  def voice_grant
    grant = Twilio::JWT::AccessToken::VoiceGrant.new
    grant.outgoing_application_sid = channel.twiml_app_sid
    grant.incoming_allow = false
    grant
  end
end
