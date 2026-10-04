require 'rails_helper'

RSpec.describe Mercadolibre::TokenService do
  let(:channel) { create(:channel_mercadolibre) }
  let(:seller) { channel.mercadolibre_seller }

  it 'returns the stored token while it is fresh' do
    expect(described_class.new(seller: seller).access_token).to eq('APP_USR-access')
  end

  it 'refreshes an expiring token and stores the rotated refresh token' do
    seller.update!(expires_at: 1.minute.from_now)
    stub_request(:post, 'https://api.mercadolibre.com/oauth/token')
      .with(body: hash_including('grant_type' => 'refresh_token', 'refresh_token' => 'TG-refresh'))
      .to_return(status: 200, body: { access_token: 'APP_USR-new', refresh_token: 'TG-new', expires_in: 21_600, user_id: seller.seller_id }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    expect(described_class.new(seller: seller).access_token).to eq('APP_USR-new')
    expect(seller.reload).to have_attributes(refresh_token: 'TG-new')
    expect(seller.expires_at).to be > 5.hours.from_now
  end

  it 'asks for reauthorization when the refresh token was revoked' do
    seller.update!(expires_at: 1.minute.ago)
    stub_request(:post, 'https://api.mercadolibre.com/oauth/token')
      .to_return(status: 400, body: { error: 'invalid_grant', message: 'invalid_grant' }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect { described_class.new(seller: seller).access_token }.to raise_error(Mercadolibre::AuthClient::InvalidGrantError)
    expect(channel.reauthorization_required?).to be(true)
  end
end
