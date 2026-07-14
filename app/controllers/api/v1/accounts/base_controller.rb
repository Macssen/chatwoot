class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  around_action :switch_locale_using_account_locale

  private

  def restricted_by_custom_role?
    Current.account_user.custom_role_id.present? && !Current.account_user.administrator?
  end
end
