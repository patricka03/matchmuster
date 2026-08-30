class PlayerFitnessStatusesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_manager!
  before_action :require_squad_analytics_plus!
  before_action :set_player

  def update
    fitness = PlayerFitnessStatus.find_or_initialize_by(
      team: @team,
      user: @player
    )
    fitness.updated_by = current_user
    fitness.assign_attributes(fitness_params)

    if fitness.save
      render json: {
        id: fitness.id,
        user_id: fitness.user_id,
        status: fitness.status,
        note: fitness.note,
        expected_return_on: fitness.expected_return_on,
        updated_at: fitness.updated_at
      }, status: :ok
    else
      render json: { errors: fitness.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_player
    @player = User.joins(:team_memberships).find_by!(
      id: params[:user_id],
      team_memberships: { team_id: @team.id, role: "player", status: "approved" }
    )
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

    render json: { error: "Only an approved team manager can update fitness status." },
           status: :forbidden
  end

  def require_squad_analytics_plus!
    require_plus!(team: @team, feature: :squad_analytics)
  end

  def fitness_params
    params.require(:player_fitness_status).permit(:status, :note, :expected_return_on)
  end
end
