class SquadAnalyticsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_manager!
  before_action :require_squad_analytics_plus!

  def show
    render json: SquadAnalytics.new(team: @team).call, status: :ok
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def authorize_manager!
    membership = current_user.team_memberships.find_by(
      team_id: @team.id,
      role: "manager",
      status: "approved"
    )

    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved" &&
              membership

    render json: { error: "Only an approved team manager can view squad analytics." },
           status: :forbidden
  end

  def require_squad_analytics_plus!
    require_plus!(team: @team, feature: :squad_analytics)
  end
end
