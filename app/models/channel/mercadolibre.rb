# == Schema Information
#
# Table name: channel_mercadolibre
#
#  id                     :bigint           not null, primary key
#  flow                   :integer          default("pre_sale"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :integer          not null
#  mercadolibre_seller_id :bigint           not null
#
# Indexes
#
#  index_channel_mercadolibre_on_mercadolibre_seller_id_and_flow  (mercadolibre_seller_id,flow) UNIQUE
#
# One MercadoLibre seller authorization feeds up to two inboxes:
# pre_sale handles item questions, post_sale handles order messaging.
class Channel::Mercadolibre < ApplicationRecord
  include Channelable
  include Reauthorizable
  self.table_name = 'channel_mercadolibre'

  AUTHORIZATION_ERROR_THRESHOLD = 1

  belongs_to :mercadolibre_seller

  enum :flow, { pre_sale: 0, post_sale: 1 }

  validates :flow, uniqueness: { scope: :mercadolibre_seller_id }

  delegate :seller_id, :site_id, :client, to: :mercadolibre_seller

  def name
    'MercadoLibre'
  end
end
