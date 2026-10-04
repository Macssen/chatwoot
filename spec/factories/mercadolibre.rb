# frozen_string_literal: true

FactoryBot.define do
  factory :mercadolibre_app do
    account
    sequence(:app_id) { |n| 1_000_000 + n }
    app_secret { SecureRandom.hex(16) }
  end

  factory :mercadolibre_seller do
    mercadolibre_app
    account { mercadolibre_app.account }
    sequence(:seller_id) { |n| 5_000_000 + n }
    nickname { 'TESTSELLER' }
    access_token { 'APP_USR-access' }
    refresh_token { 'TG-refresh' }
    expires_at { 6.hours.from_now }
  end

  factory :channel_mercadolibre, class: 'Channel::Mercadolibre' do
    mercadolibre_seller
    account { mercadolibre_seller.account }
    flow { :pre_sale }

    after(:create) do |channel|
      create(:inbox, channel: channel, account: channel.account)
    end
  end
end
