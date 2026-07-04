# WhatsApp Business Calling API surface for WhatsappCloudService.
# https://developers.facebook.com/docs/whatsapp/cloud-api/calling
module Whatsapp::Providers::WhatsappCloudCalling
  # Toggles the calling feature on the business phone number ('ENABLED'/'DISABLED').
  def update_calling_status(status)
    response = HTTParty.post(
      "#{phone_id_path('v24.0')}/settings",
      headers: api_headers,
      body: { calling: { status: status } }.to_json
    )
    raise Voice::CallErrors::CallFailed, error_message(response) unless response.success?

    response
  end

  # Starts a business-initiated call. Returns Meta's call id (wacid).
  def initiate_call(to:, sdp_offer:)
    response = calls_request(action: 'connect', to: to, session: { sdp_type: 'offer', sdp: sdp_offer })
    response.parsed_response&.dig('calls', 0, 'id')
  end

  # Warms up the media session before the user notices — reduces pickup latency.
  def pre_accept_call(call_id:, sdp_answer:)
    calls_request(action: 'pre_accept', call_id: call_id, session: { sdp_type: 'answer', sdp: sdp_answer })
  end

  def accept_call(call_id:, sdp_answer:)
    calls_request(action: 'accept', call_id: call_id, session: { sdp_type: 'answer', sdp: sdp_answer })
  end

  def reject_call(call_id:)
    calls_request(action: 'reject', call_id: call_id)
  end

  def terminate_call(call_id:)
    calls_request(action: 'terminate', call_id: call_id)
  end

  # Interactive message asking the contact to allow business-initiated calls.
  def send_call_permission_request(phone_number, body_text)
    response = HTTParty.post(
      "#{phone_id_path('v24.0')}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: phone_number,
        type: 'interactive',
        interactive: {
          type: 'call_permission_request',
          action: { name: 'call_permission_request' },
          body: { text: body_text }
        }
      }.to_json
    )
    raise Voice::CallErrors::CallFailed, error_message(response) unless response.success?

    response
  end

  private

  def calls_request(action:, **payload)
    response = HTTParty.post(
      "#{phone_id_path('v24.0')}/calls",
      headers: api_headers,
      body: { messaging_product: 'whatsapp', action: action }.merge(payload.compact).to_json
    )
    unless response.success?
      raise Voice::CallErrors::NoCallPermission, error_message(response) if error_code(response) == Voice::CallErrors::META_NO_PERMISSION_CODE

      raise Voice::CallErrors::CallFailed, "#{action}: #{error_message(response)}"
    end

    response
  end

  def error_code(response)
    response.parsed_response&.dig('error', 'code')
  end
end
