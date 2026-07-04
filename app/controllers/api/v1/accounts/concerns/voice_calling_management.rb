# Inbox-level voice calling management: WhatsApp calling toggles, the
# inbound-calls switch, and creation of Twilio-backed voice channels.
module Api::V1::Accounts::Concerns::VoiceCallingManagement
  extend ActiveSupport::Concern

  def enable_whatsapp_calling
    @inbox.channel.enable_voice_calling!
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def disable_whatsapp_calling
    @inbox.channel.disable_voice_calling!
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Toggles inbound ringing on any voice-capable channel (WhatsApp or Twilio);
  # provider_config is jsonb on both.
  def set_inbound_calls
    channel = @inbox.channel
    return head :unprocessable_entity unless channel.respond_to?(:inbound_calls_enabled?)

    enabled = ActiveModel::Type::Boolean.new.cast(params.require(:inbound_calls_enabled))
    channel.provider_config = (channel.provider_config || {}).merge('inbound_calls_enabled' => enabled)
    channel.save!(validate: false)
    head :ok
  end

  private

  # Voice channels ride on Channel::TwilioSms; the dashboard sends the Twilio
  # credentials nested under provider_config.
  def create_voice_channel
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('channel_voice')

    config = params.require(:channel).require(:provider_config).permit(:account_sid, :auth_token, :api_key_sid, :api_key_secret)
    Current.account.twilio_sms.create!(
      phone_number: params[:channel][:phone_number],
      account_sid: config[:account_sid],
      auth_token: config[:auth_token],
      api_key_sid: config[:api_key_sid],
      api_key_secret: config[:api_key_secret],
      voice_enabled: true
    )
  end
end
