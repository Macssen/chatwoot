# Access tokens last 6 hours and refresh tokens are single use, so refreshes are serialized per seller:
# two concurrent refreshes would invalidate each other and leave the seller disconnected.
class Mercadolibre::TokenService
  REFRESH_MARGIN = 10.minutes
  LOCK_WAIT_ATTEMPTS = 10

  pattr_initialize [:seller!]

  def access_token
    return seller.access_token if token_fresh?

    refresh_access_token
  end

  private

  def token_fresh?
    REFRESH_MARGIN.from_now < seller.expires_at
  end

  def refresh_access_token
    lock_manager = Redis::LockManager.new
    return wait_for_concurrent_refresh unless lock_manager.lock(lock_key, 30.seconds)

    begin
      seller.reload
      return seller.access_token if token_fresh?

      store_refreshed_tokens
    rescue Mercadolibre::AuthClient::InvalidGrantError
      seller.prompt_reauthorization!
      raise
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  def store_refreshed_tokens
    tokens = Mercadolibre::AuthClient.new(app: seller.mercadolibre_app).refresh(seller.refresh_token)
    seller.update!(tokens.except(:seller_id))
    seller.access_token
  end

  def wait_for_concurrent_refresh
    LOCK_WAIT_ATTEMPTS.times do
      sleep 0.5
      seller.reload
      return seller.access_token if token_fresh?
    end
    raise "Timed out waiting for MercadoLibre token refresh of seller #{seller.seller_id}"
  end

  def lock_key
    format(::Redis::Alfred::MERCADOLIBRE_REFRESH_TOKEN_MUTEX, seller_id: seller.seller_id)
  end
end
