class SquadSelectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_match

  before_action :authorize_team_member!,
                only: :index

  before_action :authorize_manager!,
                only: %i[
                  create
                  update
                  destroy
                ]

  before_action :set_squad_selection,
                only: %i[
                  update
                  destroy
                ]

  def index
    @squad_selections =
      @match
        .squad_selections
        .includes(:user)
        .order(:id)

    render json: {
      squad_selections:
        @squad_selections.map do |selection|
          squad_selection_json(selection)
        end
    }, status: :ok
  end

  def create
    @squad_selection =
      @match.squad_selections.new(
        squad_selection_params
      )

    if @squad_selection.save
      create_squad_selected_notification

      render json: {
        squad_selection:
          squad_selection_json(
            @squad_selection
          )
      }, status: :created
    else
      render json: {
        errors:
          @squad_selection
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    previous_user =
      @squad_selection.user

    if @squad_selection.update(
      squad_selection_params
    )
      if important_squad_details_changed?
        selected_user =
          User.find(
            @squad_selection.user_id
          )

        create_squad_updated_notification(
          recipient: selected_user
        )

        if @squad_selection.saved_change_to_user_id? &&
           previous_user.id != selected_user.id
          create_squad_updated_notification(
            recipient: previous_user
          )
        end
      end

      render json: {
        squad_selection:
          squad_selection_json(
            @squad_selection
          )
      }, status: :ok
    else
      render json: {
        errors:
          @squad_selection
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    removed_player =
      @squad_selection.user

    SquadSelection.transaction do
      @squad_selection.destroy!

      NotificationEvents.squad_published(
        match: @match,
        actor: current_user,
        updated: true,
        recipient: removed_player
      )
    end

    head :no_content
  end

  private

  def set_team
    @team = Team.find(
      params[:team_id]
    )
  end

  def set_match
    @match = @team.matches.find(
      params[:match_id]
    )
  end

  def set_squad_selection
    @squad_selection =
      @match.squad_selections.find(
        params[:id]
      )
  end

  # Approved players and approved managers may view the squad.
  # Only managers reach create, update or destroy.
  def authorize_team_member!
    membership =
      current_user
        .team_memberships
        .find_by(
          team_id: @team.id,
          status: "approved"
        )

    authorised =
      case current_user.account_type
      when "player"
        membership&.role == "player"
      when "manager"
        membership&.role == "manager" &&
          current_user.manager_verification_status == "approved"
      else
        false
      end

    return if authorised

    render json: {
      error: "You are not authorised to view this squad"
    }, status: :forbidden
  end

  def authorize_manager!
    verified_manager =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved"

    approved_manager_membership =
      current_user.team_memberships.exists?(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )

    return if verified_manager &&
              approved_manager_membership

    render json: {
      error: "You are not authorised to manage this squad"
    }, status: :forbidden
  end

  def squad_selection_params
    params.require(
      :squad_selection
    ).permit(
      :user_id,
      :selection_type,
      :position,
      :captain,
      :is_left_corner_taker,
      :is_right_corner_taker,
      :is_penalty_taker,
      :is_freekick_taker
    )
  end

  def squad_selection_json(selection)
    {
      id: selection.id,
      match_id: selection.match_id,
      user_id: selection.user_id,
      selection_type: selection.selection_type,
      position: selection.position,
      captain: selection.captain,
      is_left_corner_taker: selection.is_left_corner_taker,
      is_right_corner_taker: selection.is_right_corner_taker,
      is_penalty_taker: selection.is_penalty_taker,
      is_freekick_taker: selection.is_freekick_taker,
      user: {
        id: selection.user.id,
        first_name: selection.user.first_name,
        last_name: selection.user.last_name,
        email: selection.user.email,
        avatar_url:
          selection.user.avatar.attached? ?
            url_for(selection.user.avatar) :
            nil
      }
    }
  end

  def create_squad_selected_notification
    NotificationEvents.squad_published(
      match: @match,
      actor: current_user,
      recipient: @squad_selection.user
    )
  end

  def create_squad_updated_notification(
    recipient: @squad_selection.user
  )
    NotificationEvents.squad_published(
      match: @match,
      actor: current_user,
      updated: true,
      recipient: recipient
    )
  end

  def important_squad_details_changed?
    important_fields = %w[
      user_id
      selection_type
      position
      captain
      is_left_corner_taker
      is_right_corner_taker
      is_penalty_taker
      is_freekick_taker
    ]

    (
      @squad_selection.saved_changes.keys &
      important_fields
    ).any?
  end
end
