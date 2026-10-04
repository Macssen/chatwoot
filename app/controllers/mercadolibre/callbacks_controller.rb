# Completes the MercadoLibre OAuth flow. A seller authorization is shared by the pre_sale and post_sale inboxes:
# connecting the second flow reuses the seller record and only refreshes its tokens.
class Mercadolibre::CallbacksController < ApplicationController
  include Mercadolibre::IntegrationHelper

  def show
    return redirect_to_error_page('invalid_state', 'The authorization link expired, please try again') if state.blank?
    return redirect_to_error_page(params[:error], params[:error_description] || 'User cancelled the authorization') if params[:error].present?

    redirect_to_inbox(*connect_channel)
  rescue StandardError => e
    Rails.logger.error("MercadoLibre channel creation error: #{e.message}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    redirect_to_error_page(e.class.name, e.message)
  end

  private

  def redirect_to_inbox(channel, already_exists)
    if already_exists
      redirect_to app_mercadolibre_inbox_settings_url(account_id: account.id, inbox_id: channel.inbox.id)
    else
      redirect_to app_mercadolibre_inbox_agents_url(account_id: account.id, inbox_id: channel.inbox.id)
    end
  end

  def connect_channel
    ActiveRecord::Base.transaction do
      seller = upsert_seller
      channel = seller.channel_for(flow)
      already_exists = channel.present?
      channel ||= create_channel_with_inbox(seller)
      seller.reauthorized!
      [channel, already_exists]
    end
  end

  def upsert_seller
    seller = MercadolibreSeller.find_or_initialize_by(seller_id: tokens[:seller_id])
    raise 'This MercadoLibre seller is already connected to another account' if seller.persisted? && seller.account_id != account.id

    profile = Mercadolibre::Client.new(access_token: tokens[:access_token]).me
    seller.update!(
      account: account,
      mercadolibre_app: app,
      nickname: profile['nickname'],
      site_id: profile['site_id'],
      **tokens.slice(:access_token, :refresh_token, :expires_at)
    )
    seller
  end

  def create_channel_with_inbox(seller)
    channel = Channel::Mercadolibre.create!(account: account, mercadolibre_seller: seller, flow: flow)
    label = flow == 'pre_sale' ? 'Preguntas' : 'Posventa'
    account.inboxes.create!(channel: channel, name: "MercadoLibre #{label} (#{seller.nickname})")
    channel
  end

  def redirect_to_error_page(error_type, error_message)
    return head(:unprocessable_entity) if account.blank?

    redirect_to app_new_mercadolibre_inbox_url(account_id: account.id, error_type: error_type, error_message: error_message)
  end

  def tokens
    @tokens ||= Mercadolibre::AuthClient.new(app: app).exchange_code(params[:code])
  end

  def state
    @state ||= decode_mercadolibre_state(params[:state])
  end

  def flow
    state['flow']
  end

  def account
    @account ||= state && Account.find(state['sub'])
  end

  def app
    @app ||= account.mercadolibre_app
  end
end
