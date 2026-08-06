class AvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_match, only: %i[index create mine remind]
  before_action :set_availability, only: :update
  before_action :approved_player, only: %i[create update mine]
  before_action :approved_team_manager, only: %i[index remind]

  def index
  approved_memberships =
    @team.team_memberships
         .includes(:user)
         .where(role: "player", status: "approved")

  availability_by_user_id =
    @match.availabilities.index_by(&:user_id)

  players = approved_memberships.map do |membership|
    user = membership.user
    availability = availability_by_user_id[user.id]

    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      preferred_position: membership.preferred_position,
      availability_id: availability&.id,
      status: availability&.status || "pending"
    }
  end

  render json: {
    match: {
      id: @match.id,
      opponent: @match.opponent,
      match_type: @match.match_type,
      location: @match.location,
      kickoff_time: @match.kickoff_time
    },
    players: players,
    summary: {
      available: players.count do |player|
        player[:status] == "available"
      end,
      unavailable: players.count do |player|
        player[:status] == "unavailable"
      end,
      awaiting_response: players.count do |player|
        player[:status] == "pending"
      end,
      total_players: players.count
    }
  }, status: :ok
end

  def create
    @availability = @match.availabilities.new(availability_params)
    @availability.user = current_user

    if @availability.save
      render json: @availability, status: :created
    elsif @availability.errors.added?(:user_id, :taken)
      render json: {
        error: "You have already submitted your availability for this match"
      }, status: :unprocessable_entity
    else
      render json: {
        errors: @availability.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @availability.update(availability_params)
      render json: @availability, status: :ok
    else
      render json: {
        errors: @availability.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def remind
    responded_user_ids = @match.availabilities.select(:user_id)

    players_to_remind =
      @match.team.team_memberships
            .includes(:user)
            .where(role: "player", status: "approved")
            .where.not(user_id: responded_user_ids)

    if players_to_remind.none?
      return render json: {
        message: "All approved players have already updated their availability"
      }, status: :ok
    end

    players_to_remind.each do |membership|
      Notification.create!(
        user: membership.user,
        match: @match,
        title: "Availability Reminder",
        message: "Please confirm your availability for the match against #{@match.opponent}.",
        notification_type: "availability_reminder"
      )
    end

    @match.update!(
      availability_reminder_sent_at: Time.current
    )

    render json: {
      message: "Availability reminder sent",
      recipients: players_to_remind.count
    }, status: :ok
  end

  def mine
    availability = @match.availabilities.find_by(
      user: current_user
    )

    if availability
      render json: availability, status: :ok
    else
      render json: {
        error: "You have not submitted your availability for this match"
      }, status: :not_found
    end
  end

  private

  def set_match
    @team = Team.find(params[:team_id])
    @match = @team.matches.find(params[:match_id])
  end

  def set_availability
    @availability = current_user.availabilities.find(params[:id])
    @match = @availability.match
    @team = @match.team
  end

  def approved_player
    player_membership = current_user.team_memberships.exists?(
      team: @match.team,
      role: "player",
      status: "approved"
    )

    return if current_user.account_type == "player" &&
              player_membership

    render json: {
      error: "Only an approved player of this team can perform this action"
    }, status: :forbidden
  end

  def approved_team_manager
    manager_membership = current_user.team_memberships.exists?(
      team: @match.team,
      role: "manager",
      status: "approved"
    )

    approved_manager =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved" &&
      manager_membership

    return if approved_manager

    render json: {
      error: "Only an approved manager of this team can perform this action"
    }, status: :forbidden
  end

  def players_without_availability
    approved_players = @match.team.team_memberships
                             .includes(:user)
                             .where(
                               role: "player",
                               status: "approved"
                             )
                             .map(&:user)

    responding_user_ids = @match.availabilities.pluck(:user_id)

    approved_players.reject do |player|
      responding_user_ids.include?(player.id)
    end
  end

  def availability_params
    params.require(:availability).permit(:status)
  end

end
