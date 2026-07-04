class Api::V1::Accounts::WhatsappCallsController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::CallAlreadyAccepted, with: :render_error_response
  rescue_from Voice::CallErrors::CallFailed, with: :render_call_failed

  before_action :set_call, except: [:initiate]

  def show
    render json: {
      id: @call.id,
      call_id: @call.provider_call_id,
      status: @call.status,
      sdp_offer: @call.sdp_offer,
      ice_servers: @call.ice_servers.presence || Call.default_ice_servers
    }
  end

  def accept
    Whatsapp::CallService.new(call: @call, user: current_user).accept(params.require(:sdp_answer))
    render json: { id: @call.id, status: @call.reload.status }
  end

  def reject
    Whatsapp::CallService.new(call: @call, user: current_user).reject
    render json: { id: @call.id, status: @call.reload.status }
  end

  def terminate
    Whatsapp::CallService.new(call: @call, user: current_user).terminate
    render json: { id: @call.id, status: @call.reload.status }
  end

  # Client-side mixed recording, uploaded once the call ends. First write wins —
  # the browser may retry (pagehide beacon + explicit upload) with the same blob.
  def upload_recording
    if @call.recording.attached?
      head :ok
      return
    end

    @call.recording.attach(params.require(:recording))
    dispatch_message_update
    head :ok
  end

  def initiate
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    authorize conversation.inbox, :show?

    result = Whatsapp::OutboundCallService.new(
      conversation: conversation,
      user: current_user,
      sdp_offer: params.require(:sdp_offer)
    ).perform

    if result.call
      render json: { id: result.call.id, call_id: result.call.provider_call_id, status: result.call.status }
    else
      render json: { status: result.permission_status }, status: :unprocessable_entity
    end
  end

  private

  def set_call
    @call = Current.account.calls.whatsapp.find(params[:id])
    authorize @call.inbox, :show?
  end

  def dispatch_message_update
    message = @call.message
    return if message.blank?

    Rails.configuration.dispatcher.dispatch(Events::Types::MESSAGE_UPDATED, Time.zone.now, message: message.reload)
  end

  def render_call_failed(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end
end
