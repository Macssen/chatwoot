class MercadolibreSeller < ApplicationRecord
  belongs_to :account
  belongs_to :mercadolibre_app
  has_many :channels, class_name: 'Channel::Mercadolibre', dependent: :destroy

  if Chatwoot.encryption_configured?
    encrypts :access_token
    encrypts :refresh_token
  end

  validates :seller_id, presence: true, uniqueness: true
  validates :access_token, :refresh_token, :expires_at, presence: true

  def validated_access_token
    Mercadolibre::TokenService.new(seller: self).access_token
  end

  def client
    Mercadolibre::Client.new(access_token: validated_access_token)
  end

  def channel_for(flow)
    channels.find_by(flow: flow)
  end

  def prompt_reauthorization!
    channels.each(&:prompt_reauthorization!)
  end

  def reauthorized!
    channels.each(&:reauthorized!)
  end
end
