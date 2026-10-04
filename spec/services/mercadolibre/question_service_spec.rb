require 'rails_helper'

RSpec.describe Mercadolibre::QuestionService do
  let(:channel) { create(:channel_mercadolibre, flow: :pre_sale) }
  let(:question) do
    { id: 111, item_id: 'MLA1', status: 'UNANSWERED', text: 'Tenés stock?', from: { id: 999 }, answer: nil }
  end

  before do
    stub_request(:get, 'https://api.mercadolibre.com/questions/111?api_version=4').to_return(json(question))
    stub_request(:get, 'https://api.mercadolibre.com/users/999').to_return(json(id: 999, nickname: 'COMPRADOR1'))
    stub_request(:get, 'https://api.mercadolibre.com/items/MLA1')
      .to_return(json(title: 'Zapatillas', permalink: 'https://articulo.mercadolibre.com.ar/MLA1'))
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  it 'creates a pending question in a conversation tied to the buyer and item' do
    described_class.new(channel: channel, question_id: '111').perform

    message = channel.inbox.messages.find_by(source_id: 'q-111')
    expect(message).to be_incoming
    expect(message.content).to eq('Tenés stock?')
    expect(message.additional_attributes['mercadolibre_answered']).to be(false)
    expect(message.sender.identifier).to eq('mercadolibre:999')
    expect(message.sender.name).to eq('COMPRADOR1')
    expect(message.conversation.additional_attributes).to include('item_id' => 'MLA1', 'item_title' => 'Zapatillas')
  end

  it 'reuses the conversation for further questions on the same item' do
    described_class.new(channel: channel, question_id: '111').perform
    stub_request(:get, 'https://api.mercadolibre.com/questions/112?api_version=4').to_return(json(question.merge(id: 112)))

    described_class.new(channel: channel, question_id: '112').perform

    expect(channel.inbox.conversations.count).to eq(1)
    expect(channel.inbox.messages.incoming.count).to eq(2)
  end

  it 'mirrors an answer given directly on MercadoLibre and closes the question' do
    described_class.new(channel: channel, question_id: '111').perform
    stub_request(:get, 'https://api.mercadolibre.com/questions/111?api_version=4')
      .to_return(json(question.merge(status: 'ANSWERED', answer: { text: 'Sí, hay stock', status: 'ACTIVE' })))

    2.times { described_class.new(channel: channel, question_id: '111').perform }

    echo = channel.inbox.messages.outgoing.sole
    expect(echo.content).to eq('Sí, hay stock')
    expect(echo.source_id).to eq('a-111')
    expect(channel.inbox.messages.find_by(source_id: 'q-111').additional_attributes['mercadolibre_answered']).to be(true)
  end

  it 'ignores moderated questions' do
    stub_request(:get, 'https://api.mercadolibre.com/questions/111?api_version=4').to_return(json(question.merge(status: 'BANNED', text: '')))

    described_class.new(channel: channel, question_id: '111').perform

    expect(channel.inbox.messages.count).to eq(0)
  end
end
