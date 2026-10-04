# OAuth against MercadoLibre using the app configured by each Chatwoot account.
# https://developers.mercadolibre.com.ar/es_ar/autenticacion-y-autorizacion
class Mercadolibre::AuthClient
  AUTHORIZE_URL = 'https://auth.mercadolibre.com.ar/authorization'.freeze
  TOKEN_URL = 'https://api.mercadolibre.com/oauth/token'.freeze

  class InvalidGrantError < StandardError; end

  pattr_initialize [:app!]

  def self.redirect_uri
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/mercadolibre/callback"
  end

  def self.notifications_url
    "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/webhooks/mercadolibre"
  end

  def authorize_url(state:)
    query = { response_type: 'code', client_id: app.app_id, redirect_uri: self.class.redirect_uri, state: state }
    "#{AUTHORIZE_URL}?#{query.to_query}"
  end

  def exchange_code(code)
    request_token(grant_type: 'authorization_code', code: code, redirect_uri: self.class.redirect_uri)
  end

  # MercadoLibre refresh tokens are single use: every refresh returns a new one that must be persisted.
  def refresh(refresh_token)
    request_token(grant_type: 'refresh_token', refresh_token: refresh_token)
  end

  private

  def request_token(params)
    response = HTTParty.post(
      TOKEN_URL,
      body: params.merge(client_id: app.app_id, client_secret: app.app_secret),
      headers: { 'Accept' => 'application/json', 'Content-Type' => 'application/x-www-form-urlencoded' }
    )
    json = response.parsed_response
    raise InvalidGrantError, json['message'] if response.code == 400 && json.is_a?(Hash) && json['error'] == 'invalid_grant'
    raise "MercadoLibre token request failed (#{response.code}): #{response.body}" unless response.success?

    {
      seller_id: json['user_id'],
      access_token: json['access_token'],
      refresh_token: json['refresh_token'],
      expires_at: Time.current + json['expires_in'].to_i.seconds
    }
  end
end
