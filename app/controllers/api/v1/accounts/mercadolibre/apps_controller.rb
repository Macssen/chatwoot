# Each account brings its own MercadoLibre app (DevCenter credentials). The secret is write-only.
class Api::V1::Accounts::Mercadolibre::AppsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization

  def show
    render json: app_json(Current.account.mercadolibre_app)
  end

  def update
    app = Current.account.mercadolibre_app || Current.account.build_mercadolibre_app
    app.update!(app_params)
    render json: app_json(app)
  end

  private

  def app_params
    params.permit(:app_id, :app_secret)
  end

  def app_json(app)
    {
      configured: app.present?,
      app_id: app&.app_id,
      redirect_uri: Mercadolibre::AuthClient.redirect_uri,
      notifications_url: Mercadolibre::AuthClient.notifications_url
    }
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
