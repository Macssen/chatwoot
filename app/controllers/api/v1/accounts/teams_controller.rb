class Api::V1::Accounts::TeamsController < Api::V1::Accounts::BaseController
  before_action :fetch_team, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @teams = scoped_teams
  end

  def show; end

  def create
    @team = Current.account.teams.new(team_params)
    @team.save!
  end

  def update
    @team.update!(team_params)
  end

  def destroy
    @team.destroy!
    head :ok
  end

  private

  def fetch_team
    @team = scoped_teams.find(params[:id])
  end

  def scoped_teams
    restricted_by_custom_role? ? Current.user.teams.where(account_id: Current.account.id) : Current.account.teams
  end

  def team_params
    params.require(:team).permit(:name, :description, :allow_auto_assign, :icon, :icon_color)
  end
end
