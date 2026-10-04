require 'rails_helper'

RSpec.describe 'Webhooks::MercadolibreController', type: :request do
  include ActiveJob::TestHelper

  it 'acknowledges and enqueues supported notifications' do
    payload = { topic: 'questions', resource: '/questions/1', user_id: 42, application_id: 7, attempts: 1 }

    expect { post '/webhooks/mercadolibre', params: payload, as: :json }
      .to have_enqueued_job(Webhooks::MercadolibreEventsJob)
      .with({ 'topic' => 'questions', 'resource' => '/questions/1', 'user_id' => 42, 'application_id' => 7 })
    expect(response).to have_http_status(:ok)
  end

  it 'acknowledges other topics without processing them' do
    expect { post '/webhooks/mercadolibre', params: { topic: 'items', resource: '/items/MLA1' }, as: :json }
      .not_to have_enqueued_job(Webhooks::MercadolibreEventsJob)
    expect(response).to have_http_status(:ok)
  end
end
