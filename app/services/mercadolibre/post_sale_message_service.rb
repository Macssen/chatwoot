# Imports a post-sale message into the post_sale inbox. One conversation per pack (or order when there is no pack).
# The buyer is always read from the order: under MeLi's messaging-agent architecture `from` can be the agent, not the buyer.
# Replies must go to whoever sent the last incoming message, so that id is kept on the conversation.
# https://developers.mercadolibre.com.ar/es_ar/mensajeria-post-venta
class Mercadolibre::PostSaleMessageService
  include Mercadolibre::ConversationHelpers

  pattr_initialize [:channel!, :message_id!]

  def perform
    return if data.blank? || data['status'] != 'available'
    return if message_exists?(message_id)
    return if outgoing? && claim_pending_outgoing_message

    create_message
  end

  private

  def data
    @data ||= begin
      response = channel.client.message(message_id)
      response['messages']&.first || response
    end
  end

  def from_user_id
    data.dig('from', 'user_id').to_s
  end

  def outgoing?
    from_user_id == channel.seller_id.to_s
  end

  def text
    data['text'].is_a?(Hash) ? data.dig('text', 'plain') : data['text']
  end

  def resources
    @resources ||= Array(data['message_resources']).to_h { |resource| [resource['name'], resource['id'].to_s] }
  end

  def pack_id
    resources['packs'] || resources['orders'] || data['resource_id'].to_s
  end

  def order
    @order ||= begin
      order_id = resources['orders'] || channel.client.pack(pack_id)['orders'].first['id']
      channel.client.order(order_id)
    rescue Mercadolibre::Client::ApiError
      # Orders outside a pack are addressed through the pack endpoints with their own id
      channel.client.order(pack_id)
    end
  end

  # Our own reply may come back through the notification before SendOnMercadolibreService stored its id.
  def claim_pending_outgoing_message
    message = channel.inbox.messages.outgoing.where(source_id: nil, content: text).where(created_at: 5.minutes.ago..).last
    message&.update!(source_id: message_id)
  end

  def create_message
    message = conversation.messages.build(
      account_id: channel.account_id,
      inbox_id: channel.inbox.id,
      message_type: outgoing? ? :outgoing : :incoming,
      content: text,
      source_id: message_id
    )
    if outgoing?
      message.status = :delivered
      message.content_attributes = { external_echo: true }
    else
      message.sender = contact_inbox.contact
      conversation.update!(additional_attributes: conversation.additional_attributes.merge('mercadolibre_reply_to' => from_user_id))
    end
    attach_files(message)
    message.save!
  end

  def attach_files(message)
    Array(data['message_attachments'] || data['attachments']).each do |attachment|
      file = channel.client.download_attachment(attachment['filename'], site_id: channel.site_id)
      message.attachments.new(
        account_id: channel.account_id,
        file_type: file.content_type.to_s.start_with?('image/') ? :image : :file,
        file: { io: file, filename: attachment['original_filename'].presence || attachment['filename'], content_type: file.content_type }
      )
    end
  end

  def contact_inbox
    @contact_inbox ||= contact_inbox_for(order.dig('buyer', 'id'))
  end

  def conversation
    @conversation ||= find_or_create_conversation(contact_inbox, 'pack_id', pack_id) do
      { order_id: order['id'].to_s, mercadolibre_reply_to: order.dig('buyer', 'id').to_s }
    end
  end
end
