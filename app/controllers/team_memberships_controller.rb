class TeamMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: %i[index create]
  before_action :set_team_membership, only: %i[approve reject destroy]

  before_action :authorize_team_member!, only: %i[index]
  before_action :authorize_team_manager!, only: %i[approve reject]
  before_action :authorize_player!, only: %i[create join]

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

    if @team_membership.save
      render json: @team_membership, status: :created
    else
      render json: {
        errors: @team_membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def join
    invite_code = join_team_params[:invite_code].strip

    @team = Team.find_by(invite_code: invite_code)

    unless @team
      render json: {
        error: "Invalid team invite code"
      }, status: :not_found

      return
    end

    existing_membership = current_user.team_memberships.find_by(
      team: @team
    )

    if existing_membership
      render json: {
        error: "You have already requested to join this team",
        membership_status: existing_membership.status
      }, status: :unprocessable_entity

      return
    end

    @team_membership = @team.team_memberships.new(
      user: current_user,
      role: "player",
      status: "pending",
      preferred_position: join_team_params[:preferred_position]
    )

    if @team_membership.save
      render json: {
        message: "Your request to join the team has been sent",
        team: @team,
        team_membership: @team_membership
      }, status: :created
    else
      render json: {
        errors: @team_membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def approve
    if @team_membership.update(status: "approved")
      render json: @team_membership, status: :ok
    else
      render json: {
        errors: @team_membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def reject
    if @team_membership.update(status: "rejected")
      render json: @team_membership, status: :ok
    else
      render json: {
        errors: @team_membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    if @team_membership.user == current_user ||
        approved_manager_of_team?

      @team_membership.destroy!

      head :no_content
    else
      render json: {
        error: "You are not authorised to remove this membership"
      }, status: :forbidden
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
end
