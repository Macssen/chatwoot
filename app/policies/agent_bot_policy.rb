class AgentBotPolicy < ApplicationPolicy
  # Bot configuration is not exposed to custom-role agents.
  def index?
    @account_user.administrator? || regular_agent?
  end

  def update?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator? || regular_agent?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def avatar?
    @account_user.administrator?
  end

  def reset_access_token?
    @account_user.administrator?
  end

  def reset_secret?
    @account_user.administrator?
  end

  private

  def regular_agent?
    @account_user.agent? && @account_user.custom_role_id.blank?
  end
end
