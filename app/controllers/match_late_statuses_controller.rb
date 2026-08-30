class MatchLateStatusesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_match, except: :matchday
  before_action :authorize_match_access!, except: :matchday

  def index
    render json: {
      match: match_json(@match),
      statuses:
        status_scope(@match).map {
          |status| status_json(status)
        },
      reporting_open: matchday_open?(@match)
    }, status: :ok
  end

  def matchday
    match = match_for_today

    unless match
      return render json: {
        match: nil,
        statuses: [],
        reporting_open: false
      }, status: :ok
    end

    unless authorized_for_match?(match)
      return render json: {
        error:
          "Running Late is available only to managers and players selected for this fixture."
      }, status: :forbidden
    end

    render json: {
      match: match_json(match),
      statuses:
        status_scope(match).map {
          |status| status_json(status)
        },
      reporting_open:
        matchday_open?(match)
    }, status: :ok
  end

  def upsert
    unless matchday_open?(@match)
      return render json: {
        error:
          "Running Late is available only on the calendar day of this fixture."
      }, status: :unprocessable_entity
    end

    status =
      @match
        .match_late_statuses
        .find_or_initialize_by(
          user: current_user
        )

    was_new = status.new_record?
    previous_minutes = status.minutes_late
    previous_note = status.note

    status.assign_attributes(late_status_params)
    status.reported_at = Time.current

    meaningful_change =
      was_new ||
      previous_minutes != status.minutes_late ||
      previous_note.to_s != status.note.to_s

    if status.save
      notify_late_update!(status) if meaningful_change

      render json: {
        status: status_json(status),
        match: match_json(@match)
      }, status:
        was_new ? :created : :ok
    else
      render json: {
        errors: status.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    unless matchday_open?(@match)
      return render json: {
        error:
          "Running Late can only be changed on the calendar day of this fixture."
      }, status: :unprocessable_entity
    end

    status =
      @match
        .match_late_statuses
        .find_by(
          user: current_user
        )

    return head :no_content unless status

    status.destroy!
    notify_on_time_update!
    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_match
    @match = @team.matches.find(params[:match_id])
  end

  def authorize_team_member!
    @membership =
      current_user
        .team_memberships
        .find_by(
          team_id: @team.id,
          status: "approved"
        )

    return if @membership

    render json: {
      error: "You are not an approved member of this team."
    }, status: :forbidden
  end

  def late_status_params
    params
      .require(:match_late_status)
      .permit(
        :minutes_late,
        :note
      )
  end

  # MATCHMUSTER_SELECTED_RUNNING_LATE_V1
  def status_scope(match)
    return match.match_late_statuses.none if late_window_closed?(match)

    allowed_user_ids =
      (
        manager_user_ids +
        selected_player_user_ids(match)
      ).uniq

    match
      .match_late_statuses
      .where(
        user_id: allowed_user_ids
      )
      .includes(
        user: :team_memberships
      )
      .order(
        minutes_late: :desc,
        updated_at: :desc
      )
  end

  def match_for_today
    zone = matchmuster_zone
    now = Time.current.in_time_zone(zone)
    start_at = zone.local(now.year, now.month, now.day)
    finish_at = start_at + 1.day

    matches =
      @team
        .matches
        .where(
          kickoff_time: start_at...finish_at,
          cancelled_at: nil
        )
        .order(:kickoff_time)
        .to_a

    return nil if matches.empty?

    upcoming_match = matches.find {
      |match| match.kickoff_time >= Time.current
    }

    upcoming_match || matches.reverse.find {
      |match| !late_window_closed?(match)
    }
  end

  def matchday_open?(match)
    return false if match.cancelled_at.present? || match.kickoff_time.blank?
    return false if late_window_closed?(match)

    zone = matchmuster_zone

    Time.current.in_time_zone(zone).to_date ==
      match.kickoff_time.in_time_zone(zone).to_date
  end

  def late_window_closed?(match)
    return true if match.kickoff_time.blank?

    Time.current >=
      match.kickoff_time + 2.hours
  end

  def matchmuster_zone
    ActiveSupport::TimeZone[
      ENV.fetch(
        "MATCHMUSTER_TIME_ZONE",
        "London"
      )
    ] || Time.zone
  end

  def status_json(status)
    membership =
      status.user.team_memberships.find {
        |team_membership|
        team_membership.team_id == @team.id
      }

    {
      id: status.id,
      match_id: status.match_id,
      user_id: status.user_id,
      minutes_late: status.minutes_late,
      note: status.note,
      reported_at: status.reported_at,
      updated_at: status.updated_at,
      role: membership&.role,
      user: {
        id: status.user.id,
        first_name: status.user.first_name,
        last_name: status.user.last_name,
        account_type: status.user.account_type
      }
    }
  end

  def match_json(match)
    {
      id: match.id,
      team_id: match.team_id,
      opponent: match.opponent,
      kickoff_time: match.kickoff_time,
      location: match.location
    }
  end

  def notify_late_update!(status)
    name = display_name(current_user)

    title =
      if @membership.role == "manager"
        "Manager #{name} is running late"
      else
        "#{name} is running late"
      end

    message =
      "#{name} expects to arrive #{status.minutes_late} " \
      "minute#{status.minutes_late == 1 ? '' : 's'} late " \
      "for #{@match.opponent}."

    message = "#{message} #{status.note}" if status.note.present?

    attributes = {
      title: title,
      message: message,
      notification_type: "match_late_update",
      actor: current_user,
      featured_user: current_user,
      match: @match
    }

    if @membership.role == "manager"
      notify_selected_players!(
        attributes
      )
    else
      NotificationDelivery.to_managers(
        team: @team,
        except: current_user,
        **attributes
      )
    end
  end

  def notify_on_time_update!
    name = display_name(current_user)

    attributes = {
      title: "#{name} updated their arrival",
      message:
        "#{name} is no longer marked as running late for #{@match.opponent}.",
      notification_type: "match_late_update",
      actor: current_user,
      featured_user: current_user,
      match: @match
    }

    if @membership.role == "manager"
      notify_selected_players!(
        attributes
      )
    else
      NotificationDelivery.to_managers(
        team: @team,
        except: current_user,
        **attributes
      )
    end
  end

  def authorize_match_access!
    return if authorized_for_match?(@match)

    render json: {
      error:
        "Running Late is available only to managers and players selected for this fixture."
    }, status: :forbidden
  end

  def authorized_for_match?(match)
    return true if @membership.role == "manager"

    @membership.role == "player" &&
      selected_for_match?(
        match,
        current_user
      )
  end

  def selected_for_match?(match, user)
    match
      .squad_selections
      .exists?(
        user_id: user.id
      )
  end

  def selected_player_user_ids(match)
    match
      .squad_selections
      .pluck(:user_id)
  end

  def manager_user_ids
    @team
      .team_memberships
      .where(
        status: "approved",
        role: "manager"
      )
      .pluck(:user_id)
  end

  def selected_player_users
    User
      .where(
        id:
          selected_player_user_ids(
            @match
          )
      )
      .where(
        deleted_at: nil,
        suspended_at: nil,
        banned_at: nil
      )
  end

  def notify_selected_players!(attributes)
    selected_player_users.find_each do |player|
      next if player.id == current_user.id

      NotificationDelivery.to_user(
        user: player,
        team: @team,
        **attributes
      )
    end
  end

  def approved_manager_user_ids
    @team
      .team_memberships
      .where(status: "approved", role: "manager")
      .pluck(:user_id)
  end

  def display_name(user)
    [user.first_name, user.last_name]
      .compact
      .join(" ")
      .presence ||
      "A team member"
  end
end
