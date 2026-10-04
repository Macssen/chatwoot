# Thin wrapper over the MercadoLibre REST API. Always build it through MercadolibreSeller#client
# so the access token is refreshed when needed.
class Mercadolibre::Client
  BASE_URL = 'https://api.mercadolibre.com'.freeze

  # Raised for 4xx answers whose body explains why MercadoLibre rejected the action (blocked conversation, moderation, ...)
  class ApiError < StandardError
    attr_reader :status

    def initialize(status, message)
      @status = status
      super(message)
    end
  end

  pattr_initialize [:access_token!]

  def me
    get('/users/me')
  end

  def user(user_id)
    get("/users/#{user_id}")
  end

  def item(item_id)
    get("/items/#{item_id}")
  end

  def question(question_id)
    get("/questions/#{question_id}", api_version: 4)
  end

  def answer(question_id, text)
    post_json('/answers', { question_id: question_id.to_i, text: text })
  end

  def message(message_id)
    get("/messages/#{message_id}", tag: 'post_sale')
  end

  def order(order_id)
    get("/orders/#{order_id}")
  end

  def pack(pack_id)
    get("/packs/#{pack_id}")
  end

  def send_message(pack_id:, seller_id:, to_user_id:, text:, attachments: [])
    body = { from: { user_id: seller_id.to_s }, to: { user_id: to_user_id.to_s }, text: text }
    body[:attachments] = attachments if attachments.present?
    post_json("/messages/packs/#{pack_id}/sellers/#{seller_id}?tag=post_sale", body)
  end

  # file must be a File/Tempfile whose path keeps the original extension: MeLi validates the format by it.
  def upload_attachment(file, site_id:)
    response = HTTParty.post(
      "#{BASE_URL}/messages/attachments?tag=post_sale&site_id=#{site_id}",
      body: { file: file },
      headers: auth_headers,
      multipart: true
    )
    parse(response)['id']
  end

  def download_attachment(attachment_id, site_id:)
    Down.download(
      "#{BASE_URL}/messages/attachments/#{attachment_id}?tag=post_sale&site_id=#{site_id}",
      headers: auth_headers
    )
  end

  private

  def get(path, query = {})
    parse(HTTParty.get("#{BASE_URL}#{path}", query: query, headers: auth_headers))
  end

  def post_json(path, body)
    parse(HTTParty.post("#{BASE_URL}#{path}", body: body.to_json, headers: auth_headers.merge('Content-Type' => 'application/json')))
  end

  def parse(response)
    return response.parsed_response if response.success?

    body = response.parsed_response
    message = body.is_a?(Hash) ? (body['message'] || body['error']) : response.body
    raise ApiError.new(response.code, message.to_s)
  end

  def auth_headers
    { 'Authorization' => "Bearer #{access_token}", 'Accept' => 'application/json' }
  end
end
