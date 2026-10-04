require 'rails_helper'

RSpec.describe 'Twilio Voice webhooks' do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account) }
  let(:phone) { channel.phone_number }

  before do
    allow_any_instance_of(Channel::TwilioSms).to receive(:sync_voice_setup) # rubocop:disable RSpec/AnyInstance
    account.enable_features!('channel_voice')
    channel
  end

  def signed_post(path, params, token: channel.auth_token)
    signature = Twilio::Security::RequestValidator.new(token).build_signature_for("http://www.example.com#{path}", params.stringify_keys)
    post path, params: params, headers: { 'X-Twilio-Signature' => signature }
  end

  describe 'signature validation' do
    let(:path) { "/twilio/voice/status/#{phone}" }
    let(:params) { { CallSid: 'CA300', CallStatus: 'busy', AccountSid: channel.account_sid } }

    before { create(:call, account: account, inbox: channel.inbox, provider_call_id: 'CA300') }

    it 'rejects unsigned requests' do
      post path, params: params

      expect(response).to have_http_status(:forbidden)
      expect(Call.find_by(provider_call_id: 'CA300').status).not_to eq('busy')
    end

    it 'rejects requests signed with another token' do
      signed_post(path, params, token: 'not-the-auth-token')

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects requests whose params were altered after signing' do
      validator = Twilio::Security::RequestValidator.new(channel.auth_token)
      signature = validator.build_signature_for("http://www.example.com#{path}", params.stringify_keys)
      post path, params: params.merge(CallStatus: 'failed'), headers: { 'X-Twilio-Signature' => signature }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /twilio/voice/call/:phone' do
    it 'creates the call and bridges the caller into a waiting conference' do
      signed_post "/twilio/voice/call/#{phone}", { CallSid: 'CA123', From: '+5491100000001', AccountSid: channel.account_sid }

      expect(response).to have_http_status(:success)
      call = Call.find_by(provider: 'twilio', provider_call_id: 'CA123')
      expect(call).to be_present
      expect(response.body).to include('<Conference', "conf_acct#{account.id}_call#{call.id}")
      expect(response.body).to include('startConferenceOnEnter="false"')
      expect(call.message.content_type).to eq('voice_call')
    end

    it 'rejects callers when inbound calls are disabled' do
      channel.update!(provider_config: { 'inbound_calls_enabled' => false })

      signed_post "/twilio/voice/call/#{phone}", { CallSid: 'CA124', From: '+5491100000001', AccountSid: channel.account_sid }

      expect(response.body).to include('<Reject')
      expect(Call.count).to eq(0)
    end

    it 'normalizes SIP caller ids from trunk INVITEs' do
      signed_post "/twilio/voice/call/#{phone}",
                  { CallSid: 'CA125', From: 'sip:+5491100000002@pbx.example.com:5060', AccountSid: channel.account_sid }

      call = Call.find_by(provider_call_id: 'CA125')
      expect(call.contact.phone_number).to eq('+5491100000002')
    end

    it 'bridges the agent leg into the requested conference' do
      call = create(:call, account: account, inbox: channel.inbox)

      signed_post "/twilio/voice/call/#{phone}",
                  { CallSid: 'CA126', is_agent: 'true', To: "conf_acct#{account.id}_call#{call.id}", AccountSid: channel.account_sid }

      expect(response.body).to include('<Conference', 'startConferenceOnEnter="true"')
    end
  end

  describe 'POST /twilio/voice/status/:phone' do
    it 'maps a completed-without-answer call to no-answer' do
      call = create(:call, account: account, inbox: channel.inbox, provider_call_id: 'CA200')

      signed_post "/twilio/voice/status/#{phone}", { CallSid: 'CA200', CallStatus: 'completed', AccountSid: channel.account_sid }

      expect(call.reload.status).to eq('no-answer')
    end
  end

  describe 'POST /twilio/voice/conference_status/:phone' do
    it 'stores the conference sid on conference-start' do
      call = create(:call, account: account, inbox: channel.inbox)

      signed_post "/twilio/voice/conference_status/#{phone}",
                  { StatusCallbackEvent: 'conference-start', FriendlyName: "conf_acct#{account.id}_call#{call.id}",
                    ConferenceSid: 'CF999', AccountSid: channel.account_sid }

      expect(call.reload.conference_sid).to eq('CF999')
    end
  end
end
