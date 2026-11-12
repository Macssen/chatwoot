# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CannedResponse do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { create(:canned_response, account: account) }

    it { is_expected.to validate_uniqueness_of(:short_code).scoped_to(:account_id) }
  end

  it 'is valid without an owner' do
    expect(build(:canned_response, account: account, created_by: nil)).to be_valid
  end

  context 'when the owner is deleted' do
    let!(:canned_response) { create(:canned_response, account: account, created_by: agent) }

    it 'keeps the canned response and clears its owner' do
      DeleteObjectJob.perform_now(agent)

      expect(User.exists?(agent.id)).to be(false)
      expect(canned_response.reload.created_by_id).to be_nil
    end

    it 'keeps the owner when the agent is only removed from the account but the user still exists' do
      create(:account_user, user: agent, account: create(:account))
      agent.account_users.find_by!(account: account).destroy!

      expect(canned_response.reload.created_by_id).to eq(agent.id)
    end
  end
end
