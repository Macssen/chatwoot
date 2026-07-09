class EnableCustomRolesFeatureFlag < ActiveRecord::Migration[7.1]
  def up
    # Update the default feature flag config so new accounts get custom_roles enabled
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if config && config.value.present?
      features = config.value.map do |f|
        if f['name'] == 'custom_roles'
          f.merge('enabled' => true, 'premium' => false)
        else
          f
        end
      end
      config.value = features
      config.save!
    end

    # Enable custom_roles for all existing accounts in batches of 100
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('custom_roles') }
    end

    GlobalConfig.clear_cache
  end
end
