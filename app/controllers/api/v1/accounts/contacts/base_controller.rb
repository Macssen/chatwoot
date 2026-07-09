class Api::V1::Accounts::Contacts::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_contact

  private

  def ensure_contact
    contacts = Contacts::PermissionFilterService.new(Current.account.contacts, Current.user, Current.account).perform
    @contact = contacts.find(params[:contact_id])
  end
end
