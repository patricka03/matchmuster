class MatchesController < ApplicationController
  before_action :authenticate_user!

  before_action :set_team,
                only: %i[
                  index
                  create
                ]

  before_action :set_match,
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
                  update
                  destroy
                ]

  # ========================================
  # INDEX
  # ========================================

  def index
    @matches =
      @team
        .matches
        .order(:kickoff_time)

    render json: @matches,
           status: :ok
  end

  # ========================================
  # SHOW
  # ========================================

  def show
    render json: @match,
           status: :ok
  end

  # ========================================
  # CREATE
  # ========================================

  def create
    @match =
      @team
        .matches
        .new(
          match_params
        )

    if @match.save
      create_fixture_notifications

      render json: @match,
             status: :created
    else
      render json: {
        errors:
          @match
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # UPDATE
  # ========================================

  def update
    if @match.update(
      match_params
    )
      if important_fixture_details_changed?
        create_fixture_update_notifications
      end

      render json: @match,
             status: :ok
    else
      render json: {
        errors:
          @match
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  # ========================================
  # DESTROY
  # ========================================

  def destroy
    team_id =
      @match.team_id

    match_id =
      @match.id

    opponent =
      @match.opponent

    @match.destroy!

    create_fixture_cancelled_notifications(
      team_id: team_id,
      match_id: match_id,
      opponent: opponent
    )

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
  # SET MATCH
  # ========================================

  def set_match
    @team =
      Team.find(
        params[:team_id]
      )

    @match =
      @team
        .matches
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
        "You are not authorised to view this fixture"
    }, status: :forbidden
  end

  # ========================================
  # MANAGER AUTHORISATION
  # ========================================

  def authorise_approved_manager
    team =
      @match ?
        @match.team :
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

  def match_params
    params
      .require(:match)
      .permit(
        :opponent,
        :match_type,
        :location,
        :kickoff_time,
        :description,
        :formation,
        :latitude,
        :longitude
      )
  end

  # ========================================
  # FIXTURE CREATED NOTIFICATIONS
  # ========================================

  def create_fixture_notifications
    FixtureNotificationJob.perform_later(
      team_id:
        @team.id,

      match_id:
        @match.id,

      title:
        "New Fixture",

      message:
        "#{fixture_description}. Please confirm your availability.",

      notification_type:
        "fixture_created",

      deduplication_key:
        "match:#{@match.id}:fixture_created"
    )
  end

  # ========================================
  # FIXTURE UPDATED NOTIFICATIONS
  # ========================================

  def create_fixture_update_notifications
    FixtureNotificationJob.perform_later(
      team_id:
        @match.team_id,

      match_id:
        @match.id,

      title:
        "Fixture Updated",

      message:
        fixture_update_message,

      notification_type:
        "fixture_updated",

      deduplication_key:
        "match:#{@match.id}:fixture_updated:#{@match.updated_at.utc.iso8601(6)}"
    )
  end

  # ========================================
  # FIXTURE CANCELLED NOTIFICATIONS
  # ========================================

  def create_fixture_cancelled_notifications(
    team_id:,
    match_id:,
    opponent:
  )
    FixtureNotificationJob.perform_later(
      team_id:
        team_id,

      title:
        "Fixture Cancelled",

      message:
        "The fixture against #{opponent} has been cancelled.",

      notification_type:
        "fixture_cancelled",

      deduplication_key:
        "match:#{match_id}:fixture_cancelled"
    )
  end

  # ========================================
  # IMPORTANT FIXTURE CHANGES
  # ========================================

  def important_fixture_details_changed?
    important_fields = %w[
      opponent
      match_type
      location
      kickoff_time
      formation
    ]

    (
      @match.saved_changes.keys &
      important_fields
    ).any?
  end

  # ========================================
  # FIXTURE DESCRIPTION
  # ========================================

  def fixture_description
    "#{@team.name} vs #{@match.opponent} at #{formatted_kickoff_time}"
  end

  # ========================================
  # FIXTURE UPDATE MESSAGE
  # ========================================

  def fixture_update_message
    changed_details = []

    if @match.saved_change_to_opponent?
      changed_details <<
        "opponent"
    end

    if @match.saved_change_to_match_type?
      changed_details <<
        "match type"
    end

    if @match.saved_change_to_location?
      changed_details <<
        "location"
    end

    if @match.saved_change_to_kickoff_time?
      changed_details <<
        "kick-off time"
    end

    if @match.saved_change_to_formation?
      changed_details <<
        "formation"
    end

    "The #{changed_details.to_sentence} for the fixture against #{@match.opponent} has changed."
  end

  # ========================================
  # KICK-OFF FORMAT
  # ========================================

  def formatted_kickoff_time
    @match
      .kickoff_time
      .strftime(
        "%A %-d %B at %H:%M"
      )
  end
end
