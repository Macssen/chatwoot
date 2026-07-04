require 'rails_helper'

RSpec.describe Whatsapp::IncomingCallService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'api_key' => 'test_key', 'phone_number_id' => 'random_id', 'calling_enabled' => true })
  end
  let(:inbox) { channel.inbox }
  # unique per example — the terminate tombstone lives in Redis, which is
  # shared across examples and runs
  let(:call_id) { "wacid.#{SecureRandom.hex(8)}" }

  before do
    account.enable_features!('channel_voice')
    # the event broadcaster needs at least one recipient with a pubsub token
    create(:user, account: account, role: :administrator)
  end

  def offer_value(id: call_id)
    {
      calls: [{ id: id, from: '5491100000001', to: '15550001111', event: 'connect', direction: 'USER_INITIATED',
                session: { sdp_type: 'offer', sdp: 'v=0 fake-sdp' } }],
      contacts: [{ wa_id: '5491100000001', profile: { name: 'Caller Person' } }]
    }
  end

  describe 'inbound offer' do
    it 'creates the call, the voice_call message and rings agents' do
      expect do
        described_class.new(inbox: inbox, value: offer_value).perform
      end.to have_enqueued_job(ActionCableBroadcastJob).with(anything, 'voice_call.incoming', anything)

      call = Call.find_by(provider: 'whatsapp', provider_call_id: call_id)
      expect(call).to be_present
      expect(call.status).to eq('ringing')
      expect(call.sdp_offer).to eq('v=0 fake-sdp')
      expect(call.message.content_type).to eq('voice_call')
      expect(call.contact.name).to eq('Caller Person')
    end

    it 'is idempotent across webhook retries' do
      described_class.new(inbox: inbox, value: offer_value).perform
      expect do
        described_class.new(inbox: inbox, value: offer_value).perform
      end.not_to change(Call, :count)
    end

    it 'rejects at the provider when inbound calls are disabled' do
      channel.update!(provider_config: channel.provider_config.merge('inbound_calls_enabled' => false))
      reject_request = stub_request(:post, %r{graph\.facebook\.com/v24\.0/.+/calls})
                       .with(body: hash_including('action' => 'reject'))
                       .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new(inbox: inbox, value: offer_value).perform

      expect(reject_request).to have_been_requested
      expect(Call.count).to eq(0)
    end
  end

  describe 'terminate' do
    it 'finalizes a live call as completed with the reported duration' do
      described_class.new(inbox: inbox, value: offer_value).perform
      call = Call.find_by(provider: 'whatsapp', provider_call_id: call_id)
      call.apply_status!(Call::STATUS_IN_PROGRESS)

      terminate_value = { calls: [{ id: call_id, event: 'terminate', status: 'COMPLETED', duration: 42 }] }
      described_class.new(inbox: inbox, value: terminate_value).perform

      expect(call.reload.status).to eq('completed')
      expect(call.duration_seconds).to eq(42)
    end

    it 'tombstones a terminate that overtakes its connect so the late offer lands terminal' do
      terminate_value = { calls: [{ id: call_id, event: 'terminate', status: 'COMPLETED' }] }
      described_class.new(inbox: inbox, value: terminate_value).perform
      described_class.new(inbox: inbox, value: offer_value).perform

      call = Call.find_by(provider: 'whatsapp', provider_call_id: call_id)
      expect(call.status).to eq('no-answer')
    end
  end

  describe 'statuses' do
    it 'marks an outbound call in-progress on ACCEPTED and notifies the initiator' do
      conversation = create(:conversation, inbox: inbox, account: account)
      call = create(:call, provider: :whatsapp, direction: :outgoing, provider_call_id: call_id,
                           conversation: conversation, account: account, inbox: inbox, contact: conversation.contact)

      expect do
        described_class.new(inbox: inbox, value: { statuses: [{ id: call_id, status: 'ACCEPTED' }] }).perform
      end.to have_enqueued_job(ActionCableBroadcastJob).with(anything, 'voice_call.outbound_accepted', anything)

      expect(call.reload.status).to eq(Call::STATUS_IN_PROGRESS)
    end
  end
end
