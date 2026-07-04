require 'rails_helper'

RSpec.describe Call do
  describe 'validations' do
    it 'rejects duplicate provider_call_id per provider' do
      call = create(:call)
      dup = build(:call, provider: call.provider, provider_call_id: call.provider_call_id, conversation: call.conversation)
      expect(dup).not_to be_valid
    end

    it 'rejects unknown statuses' do
      expect(build(:call, status: 'weird')).not_to be_valid
    end
  end

  describe '#apply_status!' do
    let(:call) { create(:call) }

    it 'stamps started_at when moving to in-progress' do
      call.apply_status!(Call::STATUS_IN_PROGRESS)
      expect(call.reload.started_at).to be_present
    end

    it 'computes duration when a live call completes' do
      call.apply_status!(Call::STATUS_IN_PROGRESS)
      call.update!(started_at: 90.seconds.ago)
      call.apply_status!('completed')
      expect(call.reload.duration_seconds).to be_between(89, 92)
    end

    it 'keeps terminal statuses sticky against late webhooks' do
      call.apply_status!('rejected', end_reason: 'agent_rejected')
      call.apply_status!(Call::STATUS_IN_PROGRESS)
      expect(call.reload.status).to eq('rejected')
      expect(call.end_reason).to eq('agent_rejected')
    end
  end

  describe '#push_event_data' do
    it 'exposes the fields the dashboard reads' do
      call = create(:call)
      data = call.push_event_data
      expect(data).to include(
        id: call.id,
        provider: 'twilio',
        provider_call_id: call.provider_call_id,
        status: 'ringing',
        direction: 'incoming',
        conversation_id: call.conversation.display_id
      )
    end
  end
end
