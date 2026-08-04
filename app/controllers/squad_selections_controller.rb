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
          only: %i[id first_name]
        }
      }
    )
  end

  def create
    @squad_selection = @match.squad_selections.new(
      squad_selection_params
    )

    if @squad_selection.save
      create_squad_selected_notification

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
      create_squad_updated_notification if important_squad_details_changed?

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
    verified_manager =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved"

    approved_manager_membership = current_user.team_memberships.exists?(
      team_id: @team.id,
      role: "manager",
      status: "approved"
    )

    return if verified_manager && approved_manager_membership

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

  def create_squad_selected_notification
    Notification.create!(
      user: @squad_selection.user,
      match: @match,
      title: "Squad Selected",
      message: squad_selected_message,
      notification_type: "squad_selected"
    )
  end

  def create_squad_updated_notification
    Notification.create!(
      user: @squad_selection.user,
      match: @match,
      title: "Squad Updated",
      message: squad_updated_message,
      notification_type: "squad_updated"
    )
  end

  def important_squad_details_changed?
    @squad_selection.saved_change_to_selection_type? ||
      @squad_selection.saved_change_to_position?
  end

  def squad_selected_message
    message = "You have been selected as a #{@squad_selection.selection_type}"

    if @squad_selection.position.present?
      message += " in #{@squad_selection.position}"
    end

    "#{message} for the match against #{@match.opponent}."
  end

  def squad_updated_message
    changed_details = []

    if @squad_selection.saved_change_to_selection_type?
      changed_details << "selection"
    end

    if @squad_selection.saved_change_to_position?
      changed_details << "position"
    end

    "Your #{changed_details.to_sentence} has been updated for the match against #{@match.opponent}."
  end
end
