class Mercadolibre::SendOnMercadolibreService < Base::SendOnChannelService
  ANSWER_MAX_LENGTH = 2000
  POST_SALE_MAX_LENGTH = 350

  private

  def channel_class
    Channel::Mercadolibre
  end

  def perform_reply
    source_id = channel.pre_sale? ? answer_question : send_post_sale_message
    message.update!(source_id: source_id)
    Messages::StatusUpdateService.new(message, 'delivered').perform
  rescue StandardError => e
    Rails.logger.error "Failed to send MercadoLibre message #{message.id}: #{e.message}"
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end

  # Every question accepts a single answer: reply to the quoted question, or else to the oldest one still pending.
  def answer_question
    raise 'MercadoLibre questions do not accept attachments.' if message.attachments.any?
    raise "MercadoLibre answers are limited to #{ANSWER_MAX_LENGTH} characters." if message.outgoing_content.to_s.length > ANSWER_MAX_LENGTH

    question_message = pending_question
    raise 'There are no unanswered MercadoLibre questions in this conversation.' if question_message.blank?

    question_id = question_message.additional_attributes['mercadolibre_question_id']
    # Flag it before calling the API so the answer notification is not imported back as an echo
    mark_answered(question_message, true)
    begin
      channel.client.answer(question_id, message.outgoing_content)
    rescue StandardError
      mark_answered(question_message, false)
      raise
    end
    "a-#{question_id}"
  end

  def pending_question
    questions = conversation.messages.incoming
                            .where("messages.additional_attributes->>'mercadolibre_answered' = 'false'")
                            .order(:created_at)
    quoted_source_id = message.content_attributes['in_reply_to_external_id']
    (quoted_source_id.present? && questions.find_by(source_id: quoted_source_id)) || questions.first
  end

  def mark_answered(question_message, answered)
    question_message.update!(additional_attributes: question_message.additional_attributes.merge('mercadolibre_answered' => answered))
  end

  def send_post_sale_message
    text = message.outgoing_content.to_s
    raise "MercadoLibre post-sale messages are limited to #{POST_SALE_MAX_LENGTH} characters." if text.length > POST_SALE_MAX_LENGTH

    response = channel.client.send_message(
      pack_id: conversation.additional_attributes['pack_id'],
      seller_id: channel.seller_id,
      to_user_id: conversation.additional_attributes['mercadolibre_reply_to'],
      text: text,
      attachments: upload_attachments
    )
    response['id'] || response.dig('messages', 0, 'id')
  end

  def upload_attachments
    message.attachments.map do |attachment|
      attachment.file.open { |file| channel.client.upload_attachment(file, site_id: channel.site_id) }
    end
  end
end
