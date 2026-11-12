class CannedResponsePolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    @account_user.administrator? || @account_user.custom_role_id.nil?
  end

  def update?
    @account_user.administrator? || (@account_user.custom_role_id.nil? && record.created_by_id == @user.id)
  end

  def destroy?
    update?
  end
end
