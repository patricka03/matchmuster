class MatchesController < ApplicationController
  before_action :set_team, only: %i[index create]
  before_action :set_match, only: %i[show update destroy]
  before_action :authorise_approved_manager, only: %i[create update destroy]

  def index
    @matches = @team.matches

    render json: @matches, status: :ok
  end

  def show
    render json: @match, status: :ok
  end

  def create
    @match = @team.matches.new(match_params)

    if @match.save
      render json: @match, status: :created
    else
      render json: {
        errors: @match.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @match.update(match_params)
      render json: @match, status: :ok
    else
      render json: {
        errors: @match.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @match.destroy

    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_match
    @team = Team.find(params[:team_id])
    @match = @team.matches.find(params[:id])
  end

  def authorise_approved_manager
    team = @match ? @match.team : @team

    valid_manager =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved"

    manager_membership = current_user.team_memberships.exists?(
      team_id: team.id,
      role: "manager",
      status: "approved"
    )

    return if valid_manager && manager_membership

    render json: {
      error: "Only an approved manager of this team can perform this action"
    }, status: :forbidden
  end

  def match_params
    params.require(:match).permit(
      :opponent,
      :match_type,
      :location,
      :kickoff_time
    )
  end
end
