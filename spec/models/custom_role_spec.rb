require 'rails_helper'

RSpec.describe CustomRole do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:account_users).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    it 'allows valid permissions' do
      custom_role = build(:custom_role, permissions: %w[conversation_manage contact_manage])
      expect(custom_role).to be_valid
    end

    it 'rejects unknown permissions' do
      custom_role = build(:custom_role, permissions: ['manage_everything'])
      expect(custom_role).not_to be_valid
    end
  end

  describe 'account user nullification' do
    it 'nullifies custom_role_id on account users when destroyed' do
      account = create(:account)
      custom_role = create(:custom_role, account: account)
      agent = create(:user, account: account, role: :agent)
      account_user = agent.account_users.find_by(account_id: account.id)
      account_user.update!(custom_role: custom_role)

      custom_role.destroy!

      expect(account_user.reload.custom_role_id).to be_nil
    end
  end
end
