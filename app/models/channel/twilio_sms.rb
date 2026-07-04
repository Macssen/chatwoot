# == Schema Information
#
# Table name: channel_twilio_sms
#
#  id                             :bigint           not null, primary key
#  account_sid                    :string           not null
#  api_key_secret                 :string
#  api_key_sid                    :string
#  auth_token                     :string           not null
#  content_templates              :jsonb
#  content_templates_last_updated :datetime
#  medium                         :integer          default("sms")
#  messaging_service_sid          :string
#  phone_number                   :string
#  provider_config                :jsonb
#  twiml_app_sid                  :string
#  voice_enabled                  :boolean          default(FALSE), not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_twilio_sms_on_account_sid_and_phone_number  (account_sid,phone_number) UNIQUE
#  index_channel_twilio_sms_on_messaging_service_sid         (messaging_service_sid) UNIQUE
#  index_channel_twilio_sms_on_phone_number                  (phone_number) UNIQUE
#

class Channel::TwilioSms < ApplicationRecord
  include Channelable
  include Rails.application.routes.url_helpers

  self.table_name = 'channel_twilio_sms'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :auth_token if Chatwoot.encryption_configured?

  validates :account_sid, presence: true
  # The same parameter is used to store api_key_secret if api_key authentication is opted
  validates :auth_token, presence: true

  EDITABLE_ATTRS = [
    :account_sid,
    :auth_token,
    :api_key_sid,
    :api_key_secret,
    :voice_enabled
  ].freeze

  # Must have _one_ of messaging_service_sid _or_ phone_number, and messaging_service_sid is preferred
  validates :messaging_service_sid, uniqueness: true, presence: true, unless: :phone_number?
  validates :phone_number, absence: true, if: :messaging_service_sid?
  validates :phone_number, uniqueness: true, allow_nil: true

  enum medium: { sms: 0, whatsapp: 1 }

  # Provision/tear down the Twilio-side voice wiring whenever the flag flips
  # (including creation of voice channels, which start with voice_enabled: true).
  after_save :sync_voice_setup, if: :saved_change_to_voice_enabled?

  def name
    medium == 'sms' ? 'Twilio SMS' : 'Whatsapp'
  end

  # Voice is live only when the Twilio wiring is on AND the account has the
  # channel_voice feature. Overrides the bare AR boolean predicate.
  def voice_enabled?
    self[:voice_enabled] && account.feature_enabled?('channel_voice')
  end

  # Mutes only the incoming side of calling; default on, so only an explicit false disables inbound.
  def inbound_calls_enabled?
    provider_config['inbound_calls_enabled'] != false
  end

  def voice_call_webhook_url
    twilio_voice_call_url(phone: phone_number)
  end

  def voice_status_webhook_url
    twilio_voice_status_url(phone: phone_number)
  end

  def voice_conference_status_webhook_url
    twilio_voice_conference_status_url(phone: phone_number)
  end

  def voice_recording_status_webhook_url
    twilio_voice_recording_status_url(phone: phone_number)
  end

  # Twilio REST credentials for media downloads (basic auth pair).
  def rest_credentials
    api_key_sid.present? ? [api_key_sid, voice_api_secret] : [account_sid, auth_token]
  end

  # The API secret for JWT minting; the dedicated column wins, with auth_token
  # doubling as the secret for channels created before the column existed.
  def voice_api_secret
    api_key_secret.presence || auth_token
  end

  def send_message(to:, body:, media_url: nil)
    params = send_message_from.merge(to: to, body: body)
    params[:media_url] = media_url if media_url.present?
    params[:status_callback] = twilio_delivery_status_index_url
    client.messages.create(**params)
  end

  def client
    if api_key_sid.present?
      Twilio::REST::Client.new(api_key_sid, auth_token, account_sid)
    else
      Twilio::REST::Client.new(account_sid, auth_token)
    end
  end

  private

  def sync_voice_setup
    if self[:voice_enabled]
      Twilio::VoiceWebhookSetupService.new(channel: self).perform
    else
      Twilio::VoiceTeardownService.new(channel: self).perform
    end
  end

  def send_message_from
    if messaging_service_sid?
      { messaging_service_sid: messaging_service_sid }
    else
      { from: phone_number }
    end
  end
end

Channel::TwilioSms.prepend_mod_with('Channel::TwilioSms')
