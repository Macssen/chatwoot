# The OAuth state is signed with secret_key_base (not the account's MeLi app secret)
# because the callback needs the account id before it knows which app to use.
module Mercadolibre::IntegrationHelper
  STATE_TTL = 15.minutes

  def generate_mercadolibre_state(account_id, flow)
    payload = { sub: account_id, flow: flow, exp: STATE_TTL.from_now.to_i }
    JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
  end

  def decode_mercadolibre_state(token)
    JWT.decode(token.to_s, Rails.application.secret_key_base, true, algorithm: 'HS256').first
  rescue JWT::DecodeError
    nil
  end
end
