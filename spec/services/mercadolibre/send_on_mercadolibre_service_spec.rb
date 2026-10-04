require 'rails_helper'

RSpec.describe Mercadolibre::SendOnMercadolibreService do
  let(:contact) { create(:contact, account: channel.account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '999') }
  let(:conversation) do
    create(:conversation, inbox: channel.inbox, account: channel.account, contact: contact, contact_inbox: contact_inbox,
                          additional_attributes: conversation_attributes)
  end

  def reply(content, **attrs)
    create(:message, conversation: conversation, inbox: channel.inbox, account: channel.account,
                     message_type: :outgoing, content: content, **attrs).tap { |message| message.update!(source_id: nil) }
  end

  context 'with a pre-sale inbox' do
    let(:channel) { create(:channel_mercadolibre, flow: :pre_sale) }
    let(:conversation_attributes) { { item_id: 'MLA1' } }

    def question(id)
      create(:message, conversation: conversation, inbox: channel.inbox, account: channel.account, message_type: :incoming,
                       source_id: "q-#{id}", additional_attributes: { mercadolibre_question_id: id, mercadolibre_answered: false })
    end

    it 'answers the oldest pending question' do
      question(1)
      question(2)
      answer = stub_request(:post, 'https://api.mercadolibre.com/answers').with(body: { question_id: 1, text: 'Sí' }.to_json)
      message = reply('Sí')

      described_class.new(message: message).perform

      expect(answer).to have_been_requested
      expect(message.reload).to have_attributes(status: 'delivered', source_id: 'a-1')
      expect(conversation.messages.find_by(source_id: 'q-1').additional_attributes['mercadolibre_answered']).to be(true)
    end

    it 'answers the quoted question when the agent replies to one' do
      question(1)
      quoted = question(2)
      answer = stub_request(:post, 'https://api.mercadolibre.com/answers').with(body: { question_id: 2, text: 'Rojo' }.to_json)
      message = reply('Rojo', content_attributes: { in_reply_to: quoted.id })

      described_class.new(message: message).perform

      expect(answer).to have_been_requested
    end

    it 'fails when every question is already answered' do
      message = reply('Hola')

      described_class.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('no unanswered')
    end

    it 'leaves the question pending when MercadoLibre rejects the answer' do
      question(1)
      stub_request(:post, 'https://api.mercadolibre.com/answers').to_return(status: 400, body: { message: 'invalid_question' }.to_json)
      message = reply('Sí')

      described_class.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(conversation.messages.find_by(source_id: 'q-1').additional_attributes['mercadolibre_answered']).to be(false)
    end
  end

  context 'with a post-sale inbox' do
    let(:channel) { create(:channel_mercadolibre, flow: :post_sale) }
    let(:conversation_attributes) { { pack_id: '2000001', mercadolibre_reply_to: '3037674934' } }

    it 'sends the reply to the last sender of the pack' do
      sent = stub_request(:post, "https://api.mercadolibre.com/messages/packs/2000001/sellers/#{channel.seller_id}?tag=post_sale")
             .with(body: { from: { user_id: channel.seller_id.to_s }, to: { user_id: '3037674934' }, text: 'Llega mañana' }.to_json)
             .to_return(status: 200, body: { id: 'msg-9' }.to_json, headers: { 'Content-Type' => 'application/json' })
      message = reply('Llega mañana')

      described_class.new(message: message).perform

      expect(sent).to have_been_requested
      expect(message.reload).to have_attributes(status: 'delivered', source_id: 'msg-9')
    end

    it 'fails messages longer than the seller limit' do
      message = reply('a' * 351)

      described_class.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('350')
    end
  end
end
