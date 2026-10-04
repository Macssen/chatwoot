# Imports a pre-sale question into the pre_sale inbox. One conversation per (buyer, item).
# Each question accepts exactly one answer, so the incoming message tracks whether it was answered
# (from Chatwoot or from MercadoLibre directly) in its additional_attributes.
# https://developers.mercadolibre.com.ar/es_ar/gestiona-preguntas-respuestas
class Mercadolibre::QuestionService
  include Mercadolibre::ConversationHelpers

  IGNORED_STATUSES = %w[BANNED DELETED DISABLED UNDER_REVIEW].freeze

  pattr_initialize [:channel!, :question_id!]

  def perform
    return if IGNORED_STATUSES.include?(question['status']) || question['text'].blank?

    question_message = find_question_message || create_question_message
    import_external_answer(question_message) if external_answer?(question_message)
  end

  private

  def question
    @question ||= channel.client.question(question_id)
  end

  def buyer_id
    question.dig('from', 'id') || question['buyer_id']
  end

  def find_question_message
    channel.inbox.messages.find_by(source_id: "q-#{question['id']}")
  end

  def create_question_message
    conversation.messages.create!(
      account_id: channel.account_id,
      inbox_id: channel.inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      content: question['text'],
      source_id: "q-#{question['id']}",
      additional_attributes: { mercadolibre_question_id: question['id'], mercadolibre_answered: false }
    )
  end

  # Answered on MercadoLibre without going through Chatwoot: mirror it as an outgoing echo.
  def external_answer?(question_message)
    question['status'] == 'ANSWERED' && question.dig('answer', 'text').present? &&
      !question_message.additional_attributes['mercadolibre_answered']
  end

  def import_external_answer(question_message)
    question_message.conversation.messages.create!(
      account_id: channel.account_id,
      inbox_id: channel.inbox.id,
      message_type: :outgoing,
      status: :delivered,
      content: question.dig('answer', 'text'),
      source_id: "a-#{question['id']}",
      content_attributes: { external_echo: true }
    )
    question_message.update!(additional_attributes: question_message.additional_attributes.merge('mercadolibre_answered' => true))
  end

  def contact_inbox
    @contact_inbox ||= contact_inbox_for(buyer_id)
  end

  def conversation
    find_or_create_conversation(contact_inbox, 'item_id', question['item_id']) { item_attributes }
  end

  def item_attributes
    item = channel.client.item(question['item_id'])
    { item_title: item['title'], item_permalink: item['permalink'], item_thumbnail: item['secure_thumbnail'] }
  rescue Mercadolibre::Client::ApiError
    {}
  end
end
