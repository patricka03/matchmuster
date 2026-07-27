class TeamMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: [ :index ]
  before_action :set_membership, only: [ :approve, :reject, :destroy ]
  before_action :authorise_team_member, only: [ :index ]
  before_action :authorise_approved_manager, only: [ :approve, :reject ]

  def index
    render json: @team.team_memberships, status: :ok
  end

  def create
    unless current_user.account_type == "player"
      return render json: {
        error: "Only player accounts can join a team"
      }, status: :forbidden
    end

    if current_user.team_memberships.exists?(
      status: [ "pending", "approved" ]
    )
      return render json: {
        error: "Unable to join team. You already belong to a team or have a pending request"
      }, status: :forbidden
    end

    @team = Team.find_by(invite_code: join_params[:invite_code])

    unless @team
      return render json: {
        error: "Invalid team invite code"
      }, status: :not_found
    end

    @membership = TeamMembership.new(
      user: current_user,
      team: @team,
      role: "player",
      status: "pending",
      preferred_position: join_params[:preferred_position]
    )

    if @membership.save
      render json: @membership, status: :created
    else
      render json: {
        errors: @membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def approve
    unless @membership.role == "player"
      return render json: {
        error: "Only player memberships can be approved"
      }, status: :unprocessable_entity
    end

    unless @membership.status == "pending"
      return render json: {
        error: "Only pending memberships can be approved"
      }, status: :unprocessable_entity
    end

    if @membership.update(status: "approved")
      render json: @membership, status: :ok
    else
      render json: {
        errors: @membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def reject
    unless @membership.role == "player"
      return render json: {
        error: "Only player memberships can be rejected"
      }, status: :unprocessable_entity
    end

    unless @membership.status == "pending"
      return render json: {
        error: "Only pending memberships can be rejected"
      }, status: :unprocessable_entity
    end

    if @membership.update(status: "rejected")
      render json: @membership, status: :ok
    else
      render json: {
        errors: @membership.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    unless @membership.user == current_user
      return render json: {
        error: "You can only remove your own membership"
      }, status: :forbidden
    end

    unless @membership.role == "player"
      return render json: {
        error: "Manager memberships cannot be removed through this action"
      }, status: :forbidden
    end

    @membership.destroy

    render json: {
      message: "Team membership removed successfully"
    }, status: :ok
  end

  private

  def set_team
    @team = Team.find_by(id: params[:team_id])

    return if @team

    render json: {
      error: "Team not found"
    }, status: :not_found
  end

  def set_membership
    @membership = TeamMembership.find_by(id: params[:id])

    return if @membership

    render json: {
      error: "Team membership not found"
    }, status: :not_found
  end

  def authorise_team_member
    approved_membership = current_user.team_memberships.exists?(
      team: @team,
      status: "approved"
    )

    return if approved_membership

    render json: {
      error: "You are not an approved member of this team"
    }, status: :forbidden
  end

  def authorise_approved_manager
    valid_manager_account =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved"

    manager_membership = current_user.team_memberships.exists?(
      team: @membership.team,
      role: "manager",
      status: "approved"
    )

    return if valid_manager_account && manager_membership

    render json: {
      error: "Only an approved manager of this team can perform this action"
    }, status: :forbidden
  end

  def join_params
    params.permit(:invite_code, :preferred_position)
  end
end
