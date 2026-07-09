class CannedResponsePolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
