class TeamsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: [:show, :update, :destroy]
  before_action :require_manager!, only: [:create]
  before_action :require_team_manager!, only: [:update, :destroy]

  def show
    render json: @team
  end

  def create
    @team = Team.new(team_params)
    @team.save
  end

  def update
    @team.update(team_params)
  end

  def destroy
    @team.destroy
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :invite_code, :description)
  end

  def require_manager!
    unless current_user.account_type == "manager" && current_user.manager_verification_status == "approved"
      render json: { error: "Only managers can create teams." }, status: :forbidden
    end
  end

  def require_team_manager!
    membership = @team.team_memberships.find_by(user: current_user, role: "manager", status: "approved")
    unless membership
      render json: { error: "Only the managers of this team can edit or delete this team."}, status: :forbidden
    end
  end
end
