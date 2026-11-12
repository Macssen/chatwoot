class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]
  before_action :check_authorization

  def index
    @canned_responses = canned_responses.includes(:created_by)
  end

  def create
    @canned_response = Current.account.canned_responses.create!(canned_response_params.merge(created_by: Current.user))
  end

  def update
    @canned_response.update!(canned_response_params)
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  private

  def check_authorization
    super(@canned_response || CannedResponse)
  end

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content)
  end

  def canned_responses
    if params[:search]
      Current.account.canned_responses
             .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
             .order_by_search(params[:search])

    else
      Current.account.canned_responses
    end
  end
end
