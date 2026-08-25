class TrainingsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_team,
                only: %i[
                  index
                  create
                  create_recurring
                ]

  before_action :set_training,
                only: %i[
                  show
                  update
                  destroy
                ]

  before_action :authorize_team_member!,
                only: %i[
                  index
                  show
                ]

  before_action :authorise_approved_manager,
                only: %i[
                  create
                  create_recurring
                  update
                  destroy
                ]

  # ========================================
  # INDEX
  # ========================================

  def index
    @trainings =
      @team
        .trainings
        .order(:starts_at)

    render json: @trainings,
           status: :ok
  end

  # ========================================
  # SHOW
  # ========================================

  def show
    render json: @training,
           status: :ok
  end

  # ========================================
  # CREATE ONE-OFF TRAINING — FREE
  # ========================================

  def create
    @training =
      @team
        .trainings
        .new(
          training_params
        )

    if @training.save
      render json: @training,
             status: :created
    else
      render json: {
        errors:
          @training
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # CREATE RECURRING TRAINING — PLUS
  # ========================================

  def create_recurring
    return unless require_plus!(
      team: @team,
      feature:
        :recurring_training
    )

    trainings =
      RecurringTrainingService.call(
        team: @team,
        attributes:
          training_params,
        frequency:
          recurrence_params[
            :frequency
          ],
        occurrences:
          recurrence_params[
            :occurrences
          ]
      )

    render json: {
      recurrence_group_id:
        trainings
          .first
          .recurrence_group_id,
      frequency:
        trainings
          .first
          .recurrence_frequency,
      occurrences:
        trainings.length,
      trainings: trainings
    }, status: :created

  rescue RecurringTrainingService::InvalidSchedule => error
    render json: {
      errors: [
        error.message
      ],
      code:
        "invalid_recurring_training"
    }, status: :unprocessable_entity
  end

  # ========================================
  # UPDATE
  # ========================================

  def update
    if @training.update(
      training_params
    )
      render json: @training,
             status: :ok
    else
      render json: {
        errors:
          @training
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # DESTROY
  # ========================================

  def destroy
    @training.destroy!

    head :no_content
  end

  private

  # ========================================
  # SET TEAM
  # ========================================

  def set_team
    @team =
      Team.find(
        params[:team_id]
      )
  end

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
          params[:id]
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
        "You are not authorised to view this training session"
    }, status: :forbidden
  end

  # ========================================
  # MANAGER AUTHORISATION
  # ========================================

  def authorise_approved_manager
    team =
      @training ?
        @training.team :
        @team

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
          team_id: team.id,
          role: "manager",
          status: "approved"
        )

    return if
      valid_manager &&
      manager_membership

    render json: {
      error:
        "Only an approved manager of this team can perform this action"
    }, status: :forbidden
  end

  # ========================================
  # STRONG PARAMS
  # ========================================

  def training_params
    params
      .require(:training)
      .permit(
        :title,
        :starts_at,
        :meet_time,
        :location,
        :description,
        :latitude,
        :longitude
      )
  end

  def recurrence_params
    params
      .require(:recurrence)
      .permit(
        :frequency,
        :occurrences
      )
  end
end
