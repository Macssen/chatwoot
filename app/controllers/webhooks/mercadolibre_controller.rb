# MercadoLibre notifications are not signed and only carry a resource reference. The job always re-reads the
# resource with the seller's own token, so a forged notification can at most trigger a fetch of real data.
# https://developers.mercadolibre.com.ar/es_ar/productos-recibe-notificaciones
class Webhooks::MercadolibreController < ActionController::API
  SUPPORTED_TOPICS = %w[questions messages].freeze

  def events
    if SUPPORTED_TOPICS.include?(params[:topic])
      # Small delay so our own replies store their MeLi id before the echo notification is processed
      ::Webhooks::MercadolibreEventsJob.set(wait: 3.seconds).perform_later(notification_params.to_h)
    end

    head :ok
  end

  private

  def notification_params
    params.permit(:topic, :resource, :user_id, :application_id)
  end
end
