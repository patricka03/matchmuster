class TeamMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: %i[index create]
  before_action :set_team_membership, only: %i[approve reject destroy]

  before_action :authorize_team_member!, only: %i[index]
  before_action :authorize_team_manager!, only: %i[approve reject]
  before_action :authorize_player!,
                only: %i[create join update_preferred_position]

  def index
    @team_memberships = @team.team_memberships.includes(:user)

    unless approved_manager_of_team?
      @team_memberships = @team_memberships.where(
        status: "approved"
      )
    end

    render json: @team_memberships.as_json(
      include: {
        user: {
          only: %i[id first_name last_name email]
        }
      }
    ), status: :ok
  end

  def create
    @team_membership = @team.team_memberships.new(
      team_membership_params
    )

    @team_membership.user = current_user
    @team_membership.role = "player"
    @team_membership.status = "pending"

    begin
      save_membership_and_notify_managers!

      render json: @team_membership, status: :created
    rescue ActiveRecord::RecordInvalid => error
      render json: {
        errors: error.record.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def join
    membership_params = join_team_params
    invite_code = membership_params[:invite_code].to_s.strip

    @team = Team.find_by(invite_code: invite_code)

    unless @team
      return render json: {
        error: "Invalid team invite code"
      }, status: :not_found
    end

    existing_membership = current_user.team_memberships.find_by(
      team: @team
    )

    case existing_membership&.status
    when "approved"
      return render json: {
        error: "You are already a member of this team",
        membership_status: "approved"
      }, status: :unprocessable_entity

    when "pending"
      return render json: {
        error: "Your request is already awaiting approval",
        membership_status: "pending"
      }, status: :unprocessable_entity

    when "rejected"
      @team_membership = existing_membership

      @team_membership.assign_attributes(
        status: "pending",
        preferred_position: membership_params[:preferred_position]
      )

    else
      @team_membership = @team.team_memberships.new(
        user: current_user,
        role: "player",
        status: "pending",
        preferred_position: membership_params[:preferred_position]
      )
    end

    begin
      save_membership_and_notify_managers!

      render json: {
        message: "Your request to join the team has been sent",
        team: @team,
        team_membership: @team_membership
      }, status: :created
    rescue ActiveRecord::RecordInvalid => error
      render json: {
        errors: error.record.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def approve
    update_membership_status("approved")
  end

  def reject
    update_membership_status("rejected")
  end

  def destroy
    if @team_membership.user == current_user
      @team_membership.destroy!
    elsif approved_manager_of_team?
      remove_member_and_notify!
    else
      return render json: {
        error: "You are not authorised to remove this membership"
      }, status: :forbidden
    end

    head :no_content
  rescue ActiveRecord::RecordInvalid,
        ActiveRecord::RecordNotDestroyed => error
    render json: {
      errors: error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def update_preferred_position
    membership = current_user.team_memberships.find_by(
      role: "player"
    )

    unless membership
      return render json: {
        error: "You do not have a team membership"
      }, status: :not_found
    end

    if membership.update(preferred_position_params)
      render json: {
        message: "Preferred position updated successfully",
        preferred_position: membership.preferred_position
      }, status: :ok
    else
      render json: {
        errors: membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Team not found"
    }, status: :not_found
  end

  def set_team_membership
    @team_membership = TeamMembership.find(params[:id])
    @team = @team_membership.team
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Team membership not found"
    }, status: :not_found
  end

  def authorize_team_member!
    return if approved_team_member?

    render json: {
      error: "You are not authorised to view this team's squad"
    }, status: :forbidden
  end

  def authorize_team_manager!
    return if approved_manager_of_team?

    render json: {
      error: "You are not authorised to manage this team's memberships"
    }, status: :forbidden
  end

  def authorize_player!
    return if current_user.account_type == "player"

    render json: {
      error: "Only players can request to join a team"
    }, status: :forbidden
  end

  def approved_team_member?
    if current_user.account_type == "manager"
      return approved_manager_of_team?
    end

    current_user.account_type == "player" &&
      current_user.team_memberships.exists?(
        team_id: @team.id,
        role: "player",
        status: "approved"
      )
  end

  def approved_manager_of_team?
    current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved" &&
      current_user.team_memberships.exists?(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )
  end

  def save_membership_and_notify_managers!
    TeamMembership.transaction do
      @team_membership.save!
      notify_approved_managers_of_join_request!
    end
  end

  def notify_approved_managers_of_join_request!
    player_name = [
      current_user.first_name,
      current_user.last_name
    ].compact.join(" ")

    approved_team_managers.find_each do |manager|
      manager.notifications.create!(
        title: "New Team Join Request",
        message: "#{player_name} wants to join #{@team.name} as a #{@team_membership.preferred_position}.",
        notification_type: "team_join_requested"
      )
    end
  end

  def approved_team_managers
    User.joins(:team_memberships)
        .where(
          account_type: "manager",
          manager_verification_status: "approved"
        )
        .where(
          team_memberships: {
            team_id: @team.id,
            role: "manager",
            status: "approved"
          }
        )
        .distinct
  end

  def update_membership_status(status)
    TeamMembership.transaction do
      @team_membership.update!(status: status)
      notify_player_of_membership_status!(status)
    end

    render json: @team_membership, status: :ok
  rescue ActiveRecord::RecordInvalid => error
    render json: {
      errors: error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def notify_player_of_membership_status!(status)
    approved = status == "approved"

    @team_membership.user.notifications.create!(
      title: approved ?
        "Team Request Approved" :
        "Team Request Rejected",

      message: approved ?
        "Your request to join #{@team.name} has been approved. Welcome to the team!" :
        "Your request to join #{@team.name} was not approved.",

      notification_type: approved ?
        "team_join_approved" :
        "team_join_rejected"
    )
  end

  def team_membership_params
    params.require(:team_membership).permit(
      :preferred_position
    )
  end

  def join_team_params
    params.require(:team_membership).permit(
      :invite_code,
      :preferred_position
    )
  end

  def preferred_position_params
    params.require(:team_membership).permit(
      :preferred_position
    )
  end

  def remove_member_and_notify!
    removed_player = @team_membership.user
    team_name = @team.name

    TeamMembership.transaction do
      @team_membership.destroy!

      removed_player.notifications.create!(
        title: "Removed from Team",
        message: "You have been removed from #{team_name} by a team manager.",
        notification_type: "team_membership_removed"
      )
    end
  end
end
