class MatchesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: %i[index create]
  before_action :set_match, only: %i[show update destroy]
  before_action :authorize_team_member!, only: %i[index show]
  before_action :authorise_approved_manager, only: %i[create update destroy]

  def index
    @matches = @team.matches.order(:kickoff_time)

    render json: @matches, status: :ok
  end

  def show
    render json: @match, status: :ok
  end

  def create
    @match = @team.matches.new(match_params)

    if @match.save
      create_fixture_notifications

      render json: @match, status: :created
    else
      render json: {
        errors: @match.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @match.update(match_params)
      create_fixture_update_notifications if important_fixture_details_changed?

      render json: @match, status: :ok
    else
      render json: {
        errors: @match.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    create_fixture_cancelled_notifications

    @match.destroy

    head :no_content
  end

  private

  def authorize_team_member!
    approved_member = current_user.team_memberships.exists?(
      team_id: @team.id,
      status: "approved"
    )

    return if approved_member

    render json: {
      error: "You are not an approved member of this team"
    }, status: :forbidden
  end

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
      :kickoff_time,
      :description
    )
  end

  def approved_player_memberships
    @team.team_memberships
         .includes(:user)
         .where(
           role: "player",
           status: "approved"
         )
  end

  def create_fixture_notifications
    approved_player_memberships.each do |membership|
      Notification.create!(
        user: membership.user,
        match: @match,
        title: "New Fixture",
        message: "#{fixture_description}. Please confirm your availability.",
        notification_type: "fixture_created"
      )
    end
  end

  def create_fixture_update_notifications
    approved_player_memberships.each do |membership|
      Notification.create!(
        user: membership.user,
        match: @match,
        title: "Fixture Updated",
        message: fixture_update_message,
        notification_type: "fixture_updated"
      )
    end
  end

  def create_fixture_cancelled_notifications
    approved_player_memberships.each do |membership|
      Notification.create!(
        user: membership.user,
        match: @match,
        title: "Fixture Cancelled",
        message: "The fixture against #{@match.opponent} has been cancelled.",
        notification_type: "fixture_cancelled"
      )
    end
  end

  def important_fixture_details_changed?
    important_fields = %w[
      opponent
      match_type
      location
      kickoff_time
    ]

    (@match.saved_changes.keys & important_fields).any?
  end

  def fixture_description
    "#{@team.name} vs #{@match.opponent} at #{formatted_kickoff_time}"
  end

  def fixture_update_message
    changed_details = []

    changed_details << "opponent" if @match.saved_change_to_opponent?
    changed_details << "match type" if @match.saved_change_to_match_type?
    changed_details << "location" if @match.saved_change_to_location?
    changed_details << "kick-off time" if @match.saved_change_to_kickoff_time?

    "The #{changed_details.to_sentence} for the fixture against #{@match.opponent} has changed."
  end

  def formatted_kickoff_time
    @match.kickoff_time.strftime("%A %-d %B at %H:%M")
  end
end
