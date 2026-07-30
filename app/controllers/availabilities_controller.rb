class AvailabilitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_match, only: %i[index create remind]
  before_action :set_availability, only: %i[update]
  before_action :approved_player, only: %i[create update]
  before_action :approved_team_manager, only: %i[index remind]

  def index
    availabilities = @match.availabilities.includes(user: :team_memberships)

    response = availabilities.map do |availability|
      membership = availability.user.team_memberships.find do |team_membership|
        team_membership.team_id == @match.team_id &&
          team_membership.role == "player" &&
          team_membership.status == "approved"
      end

      {
        id: availability.id,
        status: availability.status,
        player: {
          id: availability.user.id,
          first_name: availability.user.first_name,
          last_name: availability.user.last_name,
          preferred_position: membership&.preferred_position
        }
      }
    end

    render json: response, status: :ok
  end

  # def show
  #   @availability = current_user.availability.find(availability_params)

  #   render json: @availability, status: :ok
  # end

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
    if @match.availability_reminder_sent_at.present?
      return render json: {
        error: "An availability reminder has already been sent for this match"
      }, status: :unprocessable_entity
    end

    players = players_without_availability

    if players.empty?
      return render json: {
        message: "Every approved player has already submitted their availability"
      }, status: :ok
    end

    players.each do |player|
      Notification.create!(
        user: player,
        title: "Availability Reminder",
        message: "Please confirm your availability for the match against #{@match.opponent}.",
        notification_type: "availability_reminder"
      )
    end

    @match.update!(availability_reminder_sent_at: Time.current)

    render json: {
      message: "Availability reminder sent",
      players_notified: players.size
    }, status: :ok
  end

  private

  def set_match
    @match = Match.find(params[:match_id])
  end

  def set_availability
    @availability = current_user.availabilities.find(params[:id])
    @match = @availability.match
  end

  def approved_player
    player_membership = current_user.team_memberships.exists?(
      team: @match.team,
      role: "player",
      status: "approved"
    )

    return if current_user.account_type == "player" && player_membership

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

    return if current_user.account_type == "manager" && manager_membership

    render json: {
      error: "Only an approved manager of this team can view availability responses"
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
