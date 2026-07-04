# Agent-initiated Twilio calls to a contact's phone number.
class Api::V1::Accounts::Contacts::CallsController < Api::V1::Accounts::BaseController
  rescue_from Voice::CallErrors::CallFailed, with: :render_call_failed

  def create
    contact = Current.account.contacts.find(params[:contact_id])
    inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize inbox, :show?

    channel = inbox.channel
    raise Voice::CallErrors::CallFailed, 'voice calling is not enabled on this inbox' unless channel.try(:voice_enabled?)
    raise Voice::CallErrors::CallFailed, 'contact has no phone number' if contact.phone_number.blank?

    conversation = resolve_conversation(contact, inbox)
    call = dial(channel, contact, conversation)

    render json: { call_sid: call.provider_call_id, conversation_id: conversation.display_id }
  end

  private

  def resolve_conversation(contact, inbox)
    return Current.account.conversations.find_by!(display_id: params[:conversation_id]) if params[:conversation_id].present?

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      source_id: contact.phone_number,
      contact_attributes: { name: contact.name, phone_number: contact.phone_number }
    ).perform
    contact_inbox.conversations.where.not(status: :resolved).last ||
      ::Conversation.create!(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id
      )
  end

  def dial(channel, contact, conversation)
    twilio_call = channel.client.calls.create(
      to: contact.phone_number,
      from: channel.phone_number,
      url: channel.voice_call_webhook_url,
      status_callback: channel.voice_status_webhook_url,
      status_callback_method: 'POST',
      status_callback_event: %w[initiated ringing answered completed]
    )

    Voice::OutboundCallBuilder.new(
      conversation: conversation,
      agent: current_user,
      provider: :twilio,
      provider_call_id: twilio_call.sid
    ).perform
  end

  def render_call_failed(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end
