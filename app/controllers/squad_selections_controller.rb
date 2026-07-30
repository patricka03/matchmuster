class SquadSelectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_match
  before_action :authorize_manager!
  before_action :set_squad_selection, only: %i[update destroy]

  def index
    @squad_selections = @match.squad_selections.includes(:user)

    render json: @squad_selections.as_json(
      include: {
        user: {
          only: %i[id name]
        }
      }
    )
  end

  def create
    @squad_selection = @match.squad_selections.new(
      squad_selection_params
    )

    if @squad_selection.save
      render json: @squad_selection,
             status: :created
    else
      render json: {
        errors: @squad_selection.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @squad_selection.update(squad_selection_params)
      render json: @squad_selection,
             status: :ok
    else
      render json: {
        errors: @squad_selection.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @squad_selection.destroy

    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_match
    @match = @team.matches.find(params[:match_id])
  end

  def set_squad_selection
    @squad_selection = @match.squad_selections.find(params[:id])
  end

  def authorize_manager!
    approved_manager = current_user.team_memberships.exists?(
      team_id: @team.id,
      role: "manager",
      status: "approved"
    )

    return if approved_manager

    render json: {
      error: "You are not authorised to manage this squad"
    }, status: :forbidden
  end

  def squad_selection_params
    params.require(:squad_selection).permit(
      :user_id,
      :selection_type,
      :position,
      :captain,
      :is_corner_taker,
      :is_penalty_taker,
      :is_freekick_taker
    )
  end
end
