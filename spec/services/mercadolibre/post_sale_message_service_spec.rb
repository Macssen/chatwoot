require 'rails_helper'

RSpec.describe Mercadolibre::PostSaleMessageService do
  let(:channel) { create(:channel_mercadolibre, flow: :post_sale) }
  let(:agent_id) { 3_037_674_934 }
  let(:message_payload) do
    {
      messages: [{
        id: 'msg-1', status: 'available', text: 'Cuándo llega?',
        from: { user_id: agent_id }, to: { user_id: channel.seller_id },
        message_resources: [{ id: '2000001', name: 'packs' }, { id: channel.seller_id.to_s, name: 'sellers' }],
        message_attachments: nil
      }]
    }
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  before do
    stub_request(:get, 'https://api.mercadolibre.com/messages/msg-1?tag=post_sale').to_return(json(message_payload))
    stub_request(:get, 'https://api.mercadolibre.com/packs/2000001').to_return(json(orders: [{ id: 3001 }]))
    stub_request(:get, 'https://api.mercadolibre.com/orders/3001').to_return(json(id: 3001, buyer: { id: 777, nickname: 'COMPRADOR' }))
    stub_request(:get, 'https://api.mercadolibre.com/users/777').to_return(json(id: 777, nickname: 'COMPRADOR'))
  end

  it 'creates the pack conversation with the buyer from the order and replies routed to the sender' do
    described_class.new(channel: channel, message_id: 'msg-1').perform

    message = channel.inbox.messages.find_by(source_id: 'msg-1')
    expect(message).to be_incoming
    expect(message.sender.identifier).to eq('mercadolibre:777')
    expect(message.conversation.additional_attributes).to include(
      'pack_id' => '2000001', 'order_id' => '3001', 'mercadolibre_reply_to' => agent_id.to_s
    )
  end

  it 'does not import the same message twice' do
    2.times { described_class.new(channel: channel, message_id: 'msg-1').perform }

    expect(channel.inbox.messages.count).to eq(1)
  end

  it 'links the echo of a reply sent from Chatwoot instead of duplicating it' do
    described_class.new(channel: channel, message_id: 'msg-1').perform
    conversation = channel.inbox.conversations.sole
    reply = create(:message, conversation: conversation, inbox: channel.inbox, account: channel.account,
                             message_type: :outgoing, content: 'Mañana', source_id: nil)
    echo = message_payload[:messages].first.merge(id: 'msg-2', text: 'Mañana', from: { user_id: channel.seller_id })
    stub_request(:get, 'https://api.mercadolibre.com/messages/msg-2?tag=post_sale').to_return(json(messages: [echo]))

    described_class.new(channel: channel, message_id: 'msg-2').perform

    expect(reply.reload.source_id).to eq('msg-2')
    expect(conversation.messages.outgoing.count).to eq(1)
  end
end
