require 'rails_helper'

RSpec.describe Webhooks::MercadolibreEventsJob do
  let(:pre_sale) { create(:channel_mercadolibre, flow: :pre_sale) }
  let(:seller) { pre_sale.mercadolibre_seller }
  let!(:post_sale) { create(:channel_mercadolibre, flow: :post_sale, mercadolibre_seller: seller) }
  let(:question_service) { instance_double(Mercadolibre::QuestionService, perform: true) }
  let(:message_service) { instance_double(Mercadolibre::PostSaleMessageService, perform: true) }

  before do
    allow(Mercadolibre::QuestionService).to receive(:new).and_return(question_service)
    allow(Mercadolibre::PostSaleMessageService).to receive(:new).and_return(message_service)
  end

  def notification(topic, resource, application_id: seller.mercadolibre_app.app_id)
    { topic: topic, resource: resource, user_id: seller.seller_id, application_id: application_id }
  end

  it 'routes questions to the pre-sale inbox' do
    described_class.perform_now(notification('questions', '/questions/111'))

    expect(Mercadolibre::QuestionService).to have_received(:new).with(channel: pre_sale, question_id: '111')
  end

  it 'routes messages to the post-sale inbox' do
    described_class.perform_now(notification('messages', 'abc123'))

    expect(Mercadolibre::PostSaleMessageService).to have_received(:new).with(channel: post_sale, message_id: 'abc123')
  end

  it 'ignores notifications from an app that does not own the seller' do
    described_class.perform_now(notification('questions', '/questions/111', application_id: 1))

    expect(Mercadolibre::QuestionService).not_to have_received(:new)
  end
end
