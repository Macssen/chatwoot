class ArticlePolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def update?
    @account_user.administrator? || custom_role_permission?('knowledge_base_manage')
  end

  def show?
    @account_user.administrator? || custom_role_permission?('knowledge_base_manage')
  end

  def edit?
    @account_user.administrator? || custom_role_permission?('knowledge_base_manage')
  end

  def create?
    @account_user.administrator? || custom_role_permission?('knowledge_base_manage')
  end

  def destroy?
    @account_user.administrator? || custom_role_permission?('knowledge_base_manage')
  end

  def reorder?
    @account_user.administrator? || custom_role_permission?('knowledge_base_manage')
  end
end

ArticlePolicy.prepend_mod_with('ArticlePolicy')
