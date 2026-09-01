class AvailabilitiesController < ApplicationController
  before_action :authenticate_user!

  before_action :set_match,
                only: %i[
                  index
                  create
                  mine
                  remind
                ]

  before_action :set_availability,
                only: :update

  before_action :approved_player,
                only: %i[
                  create
                  update
                  mine
                ]

  before_action :approved_team_manager,
                only: %i[
                  index
                  remind
                ]

  before_action :require_availability_reminders_plus!,
                only: :remind

  def index
    approved_memberships =
      @team.team_memberships
           .includes(:user)
           .where(
             role: "player",
             status: "approved"
           )

    availability_by_user_id =
      @match.availabilities.index_by(
        &:user_id
      )

    suspension_by_user_id =
      @team
        .disciplinary_records
        .active_suspensions
        .where(
          player_id: approved_memberships.map(&:user_id)
        )
        .order(created_at: :desc)
        .each_with_object({}) do |record, result|
          result[record.player_id] ||= record
        end

    players =
      approved_memberships.map do |membership|
        user = membership.user

        availability =
          availability_by_user_id[
            user.id
          ]

        suspension = suspension_by_user_id[user.id]

        {
          id: user.id,
          first_name: user.first_name,
          last_name: user.last_name,
          email: user.email,

          preferred_position:
            membership.preferred_position,

          availability_id:
            availability&.id,

          status:
            availability&.status ||
            "pending",

          active_suspension:
            suspension ? {
              disciplinary_record_id: suspension.id,
              matches_remaining:
                suspension.suspension_matches_remaining,
              card_type: suspension.card_type,
              reason: suspension.reason
            } : nil
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
        available:
          players.count do |player|
            player[:status] ==
              "available"
          end,

        unavailable:
          players.count do |player|
            player[:status] ==
              "unavailable"
          end,

        awaiting_response:
          players.count do |player|
            player[:status] ==
              "pending"
          end,

        total_players:
          players.count
      }
    }, status: :ok
  end

  def create
    @availability =
      @match.availabilities.new(
        availability_params
      )

    @availability.user =
      current_user

    if @availability.save
      clear_completed_availability_notifications

      notify_team_managers_of_availability_change(
        @availability
      )

      render json: @availability,
             status: :created

    elsif @availability.errors.added?(
      :user_id,
      :taken
    )
      render json: {
        error:
          "You have already submitted your availability for this match"
      }, status: :unprocessable_entity

    else
      render json: {
        errors:
          @availability.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @availability.update(
      availability_params
    )
      clear_completed_availability_notifications

      if @availability.saved_change_to_status?
        notify_team_managers_of_availability_change(
          @availability
        )
      end

      render json: @availability,
             status: :ok
    else
      render json: {
        errors:
          @availability.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def remind
    responded_user_ids =
      @match
        .availabilities
        .select(:user_id)

    players_to_remind =
      @match
        .team
        .team_memberships
        .where(
          role: "player",
          status: "approved"
        )
        .where.not(
          user_id:
            responded_user_ids
        )

    if players_to_remind.none?
      return render json: {
        message:
          "All approved players have already updated their availability"
      }, status: :ok
    end

    AvailabilityReminderJob.perform_later(
      @match.id,
      current_user.id
    )

    render json: {
      message:
        "Availability reminder queued",

      recipients:
        players_to_remind.count
    }, status: :accepted
  end

  def mine
    availability =
      @match.availabilities.find_by(
        user: current_user
      )

    if availability
      render json: availability,
             status: :ok
    else
      render json: {
        error:
          "You have not submitted your availability for this match"
      }, status: :not_found
    end
  end

  private

  def set_match
    @team =
      Team.find(
        params[:team_id]
      )

    @match =
      @team.matches.find(
        params[:match_id]
      )
  end

  def set_availability
    @availability =
      current_user.availabilities.find(
        params[:id]
      )

    @match =
      @availability.match

    @team =
      @match.team
  end

  def approved_player
    player_membership =
      current_user
        .team_memberships
        .exists?(
          team: @match.team,
          role: "player",
          status: "approved"
        )

    return if
      current_user.account_type ==
        "player" &&
      player_membership

    render json: {
      error:
        "Only an approved player of this team can perform this action"
    }, status: :forbidden
  end

  def approved_team_manager
    manager_membership =
      current_user
        .team_memberships
        .exists?(
          team: @match.team,
          role: "manager",
          status: "approved"
        )

    approved_manager =
      current_user.account_type ==
        "manager" &&
      current_user.manager_verification_status ==
        "approved" &&
      manager_membership

    return if approved_manager

    render json: {
      error:
        "Only an approved manager of this team can perform this action"
    }, status: :forbidden
  end

  def require_availability_reminders_plus!
    require_plus!(
      team: @team,
      feature:
        :automatic_availability_reminders
    )
  end

  def clear_completed_availability_notifications
    current_user
      .notifications
      .where(
        match: @match,
        notification_type:
          Notification::AVAILABILITY_ACTION_TYPES,
        kept_at: nil
      )
      .destroy_all
  end

  def notify_team_managers_of_availability_change(
    availability
  )
    NotificationEvents.player_availability_updated(
      match: @match,
      player: current_user,
      status: availability.status,
      removed_from_squad:
        availability.removed_from_matchday_squad?
    )
  end

  def players_without_availability
    approved_players =
      @match
        .team
        .team_memberships
        .includes(:user)
        .where(
          role: "player",
          status: "approved"
        )
        .map(&:user)

    responding_user_ids =
      @match.availabilities.pluck(
        :user_id
      )

    approved_players.reject do |player|
      responding_user_ids.include?(
        player.id
      )
    end
  end

  def availability_params
    params
      .require(:availability)
      .permit(:status)
  end
end
