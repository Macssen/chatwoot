class MercadolibreApp < ApplicationRecord
  belongs_to :account
  has_many :sellers, class_name: 'MercadolibreSeller', dependent: :destroy

  encrypts :app_secret if Chatwoot.encryption_configured?

  validates :account_id, uniqueness: true
  validates :app_id, presence: true, uniqueness: true
  validates :app_secret, presence: true
  validate :app_id_locked_while_sellers_exist, on: :update

  private

  def app_id_locked_while_sellers_exist
    return unless app_id_changed? && sellers.exists?

    errors.add(:app_id, 'cannot change while MercadoLibre sellers are connected')
  end
end
