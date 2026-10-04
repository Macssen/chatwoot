class Webhooks::MercadolibreEventsJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 15

  def perform(notification)
    @notification = notification.with_indifferent_access
    return if channel.blank? || !channel.account.active?

    key = format(::Redis::Alfred::MERCADOLIBRE_EVENT_MUTEX, seller_id: seller.seller_id, topic: @notification[:topic])
    with_lock(key, 30.seconds) do
      process_notification
    end
  end

  private

  def process_notification
    if channel.pre_sale?
      Mercadolibre::QuestionService.new(channel: channel, question_id: resource_id).perform
    else
      Mercadolibre::PostSaleMessageService.new(channel: channel, message_id: resource_id).perform
    end
  end

  # questions arrive as "/questions/123", messages as the bare message id
  def resource_id
    @notification[:resource].to_s.split('/').last
  end

  def seller
    @seller ||= MercadolibreSeller.joins(:mercadolibre_app)
                                  .find_by(seller_id: @notification[:user_id], mercadolibre_apps: { app_id: @notification[:application_id] })
  end

  def channel
    @channel ||= seller&.channel_for(@notification[:topic] == 'questions' ? :pre_sale : :post_sale)
  end
end
