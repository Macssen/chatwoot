# Agent-side lifecycle of Twilio conference calls: mint the Voice SDK token,
# join (claim) a call, and leave/decline it.
class Api::V1::Accounts::ConferenceController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::CallAlreadyAccepted, with: :render_error_response
  rescue_from Voice::CallErrors::CallFailed, with: :render_call_failed

  before_action :set_inbox

  def token
    render json: {
      token: Twilio::VoiceTokenService.new(channel: @inbox.channel, user: current_user).generate,
      account_id: Current.account.id
    }
  end

  def create
    call = find_call!
    # the dashboard interprets 409 as "call already over — dismiss the card"
    return head :conflict if call.terminal?

    Voice::TwilioConferenceService.new(call: call).claim_agent!(current_user)
    render json: { conference_sid: Voice::TwilioConferenceService.conference_name(call) }
  end

  def destroy
    call = find_call!
    Voice::TwilioConferenceService.new(call: call).leave!
    head :ok
  end

  private

  def set_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def find_call!
    scope = Current.account.calls.twilio.where(inbox_id: @inbox.id)
    call = scope.find_by(provider_call_id: params[:call_sid]) if params[:call_sid].present?
    call ||= find_call_by_conversation
    raise ActiveRecord::RecordNotFound, 'call not found' if call.blank?

    call
  end

  def find_call_by_conversation
    return if params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
    return if conversation.blank?

    conversation.calls.twilio.active.order(created_at: :desc).first
  end

  def render_call_failed(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end
