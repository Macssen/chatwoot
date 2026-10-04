class AddMercadolibreChannel < ActiveRecord::Migration[7.1]
  def change
    create_apps
    create_sellers
    create_channels
  end

  private

  def create_apps
    create_table :mercadolibre_apps do |t|
      t.integer :account_id, null: false
      t.bigint :app_id, null: false
      t.string :app_secret, null: false
      t.timestamps
    end
    add_index :mercadolibre_apps, :account_id, unique: true
    add_index :mercadolibre_apps, :app_id, unique: true
  end

  def create_sellers
    create_table :mercadolibre_sellers do |t|
      t.integer :account_id, null: false
      t.references :mercadolibre_app, null: false, foreign_key: true
      t.bigint :seller_id, null: false
      t.string :nickname
      t.string :site_id, null: false, default: 'MLA'
      t.string :access_token, null: false
      t.string :refresh_token, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :mercadolibre_sellers, :seller_id, unique: true
  end

  def create_channels
    create_table :channel_mercadolibre do |t|
      t.integer :account_id, null: false
      t.references :mercadolibre_seller, null: false, foreign_key: true, index: false
      t.integer :flow, null: false, default: 0
      t.timestamps
    end
    add_index :channel_mercadolibre, [:mercadolibre_seller_id, :flow], unique: true
  end
end
