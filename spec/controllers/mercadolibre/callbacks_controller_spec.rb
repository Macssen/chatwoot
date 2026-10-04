require 'rails_helper'

RSpec.describe 'MercadoLibre Callbacks', type: :request do
  include Mercadolibre::IntegrationHelper

  let(:meli_app) { create(:mercadolibre_app) }
  let(:account) { meli_app.account }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  before do
    stub_request(:post, 'https://api.mercadolibre.com/oauth/token')
      .with(body: hash_including('grant_type' => 'authorization_code', 'code' => 'TG-code', 'client_id' => meli_app.app_id.to_s))
      .to_return(status: 200, body: { access_token: 'APP_USR-1', refresh_token: 'TG-1', expires_in: 21_600, user_id: 4242 }.to_json,
                 headers: json_headers)
    stub_request(:get, 'https://api.mercadolibre.com/users/me')
      .to_return(status: 200, body: { id: 4242, nickname: 'TIENDA', site_id: 'MLA' }.to_json, headers: json_headers)
  end

  def connect(flow)
    get '/mercadolibre/callback', params: { code: 'TG-code', state: generate_mercadolibre_state(account.id, flow) }
  end

  it 'creates the seller and the inbox for the requested flow' do
    connect('pre_sale')

    seller = MercadolibreSeller.find_by!(seller_id: 4242)
    channel = seller.channel_for(:pre_sale)
    expect(seller).to have_attributes(account_id: account.id, nickname: 'TIENDA', access_token: 'APP_USR-1')
    expect(channel.inbox.name).to eq('MercadoLibre Preguntas (TIENDA)')
    expect(response).to redirect_to(app_mercadolibre_inbox_agents_url(account_id: account.id, inbox_id: channel.inbox.id))
  end

  it 'reuses the seller when connecting the second flow' do
    connect('pre_sale')
    connect('post_sale')

    expect(MercadolibreSeller.count).to eq(1)
    expect(MercadolibreSeller.sole.channels.map(&:flow)).to contain_exactly('pre_sale', 'post_sale')
  end

  it 'refuses a seller already connected to another account' do
    create(:mercadolibre_seller, seller_id: 4242)

    connect('pre_sale')

    expect(Channel::Mercadolibre.count).to eq(0)
    expect(response.location).to include('error_message')
  end

  it 'rejects a tampered state' do
    get '/mercadolibre/callback', params: { code: 'TG-code', state: 'forged' }

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
