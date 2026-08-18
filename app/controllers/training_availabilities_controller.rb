class TrainingAvailabilitiesController < ApplicationController
  before_action :authenticate_user!

  before_action :set_training

  before_action :authorize_team_member!

  before_action :authorise_approved_manager,
                only: %i[
                  index
                ]

  before_action :authorise_player,
                only: %i[
                  mine
                  create
                  update
                ]

  before_action :set_training_availability,
                only: %i[
                  update
                ]

  # ========================================
  # INDEX
  # Manager sees every approved player,
  # including players who have not replied.
  # ========================================

  def index
    memberships =
      @team
        .team_memberships
        .where(
          role: "player",
          status: "approved"
        )
        .includes(:user)

    availability_by_user_id =
      @training
        .training_availabilities
        .index_by(&:user_id)

    players =
      memberships.map do |membership|
        availability =
          availability_by_user_id[
            membership.user_id
          ]

        {
          user_id:
            membership.user_id,

          first_name:
            membership.user.first_name,

          last_name:
            membership.user.last_name,

          preferred_position:
            membership.preferred_position,

          training_availability_id:
            availability&.id,

          status:
            availability&.status ||
            "pending"
        }
      end

    render json: {
      training_id:
        @training.id,

      players:
        players
    }, status: :ok
  end

  # ========================================
  # MY AVAILABILITY
  # ========================================

  def mine
    availability =
      @training
        .training_availabilities
        .find_by(
          user_id: current_user.id
        )

    if availability
      render json: availability,
             status: :ok
    else
      render json: {
        availability: nil
      }, status: :ok
    end
  end

  # ========================================
  # CREATE
  # ========================================

  def create
    existing_availability =
      @training
        .training_availabilities
        .find_by(
          user_id: current_user.id
        )

    if existing_availability
      return render json: {
        error:
          "You have already responded to this training session"
      }, status: :unprocessable_entity
    end

    availability =
      @training
        .training_availabilities
        .new(
          training_availability_params
        )

    availability.user =
      current_user

    if availability.save
      render json: availability,
             status: :created
    else
      render json: {
        errors:
          availability
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # UPDATE
  # ========================================

  def update
    if @training_availability.update(
      training_availability_params
    )
      render json:
        @training_availability,
        status: :ok
    else
      render json: {
        errors:
          @training_availability
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  # ========================================
  # SET TRAINING
  # ========================================

  def set_training
    @team =
      Team.find(
        params[:team_id]
      )

    @training =
      @team
        .trainings
        .find(
          params[:training_id]
        )
  end

  # ========================================
  # TEAM MEMBER AUTHORISATION
  # ========================================

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
        membership&.role ==
          "player"

      when "manager"
        membership&.role ==
          "manager" &&
          current_user
            .manager_verification_status ==
            "approved"

      else
        false
      end

    return if authorised

    render json: {
      error:
        "You are not authorised to access training availability for this team"
    }, status: :forbidden
  end

  # ========================================
  # MANAGER AUTHORISATION
  # ========================================

  def authorise_approved_manager
    valid_manager =
      current_user.account_type ==
        "manager" &&
      current_user
        .manager_verification_status ==
        "approved"

    manager_membership =
      current_user
        .team_memberships
        .exists?(
          team_id: @team.id,
          role: "manager",
          status: "approved"
        )

    return if
      valid_manager &&
      manager_membership

    render json: {
      error:
        "Only an approved manager of this team can view training availability"
    }, status: :forbidden
  end

  # ========================================
  # PLAYER AUTHORISATION
  # ========================================

  def authorise_player
    valid_player =
      current_user.account_type ==
        "player"

    player_membership =
      current_user
        .team_memberships
        .exists?(
          team_id: @team.id,
          role: "player",
          status: "approved"
        )

    return if
      valid_player &&
      player_membership

    render json: {
      error:
        "Only an approved player of this team can respond to training availability"
    }, status: :forbidden
  end

  # ========================================
  # FIND PLAYER'S OWN RESPONSE
  # ========================================

  def set_training_availability
    @training_availability =
      @training
        .training_availabilities
        .find_by!(
          id: params[:id],
          user_id: current_user.id
        )
  end

  # ========================================
  # STRONG PARAMS
  # ========================================

  def training_availability_params
    params
      .require(
        :training_availability
      )
      .permit(
        :status
      )
  end
end
