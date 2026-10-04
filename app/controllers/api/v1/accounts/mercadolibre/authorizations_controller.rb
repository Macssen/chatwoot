class Api::V1::Accounts::Mercadolibre::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include Mercadolibre::IntegrationHelper

  def create
    app = Current.account.mercadolibre_app
    return render json: { success: false, error: 'MercadoLibre app is not configured' }, status: :unprocessable_entity if app.blank?

    flow = params.require(:flow)
    raise ActionController::BadRequest, "Invalid flow: #{flow}" unless Channel::Mercadolibre.flows.key?(flow)

    url = Mercadolibre::AuthClient.new(app: app).authorize_url(state: generate_mercadolibre_state(Current.account.id, flow))
    render json: { success: true, url: url }
  end
end
