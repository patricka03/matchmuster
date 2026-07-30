class TeamMembershipsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_team, only: %i[index create]

  before_action :set_team_membership,
                only: %i[approve reject destroy]

  before_action :authorize_team_manager!,
                only: %i[index approve reject]

  def index
    @team_memberships = @team.team_memberships.includes(:user)

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
    @team_membership.status = "pending"

    if @team_membership.save
      render json: @team_membership, status: :created
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
    if @team_membership.user == current_user || manager_of_membership_team?
      @team_membership.destroy
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
  end

  def set_team_membership
    @team_membership = TeamMembership.find(params[:id])
    @team = @team_membership.team
  end

  def authorize_team_manager!
    return if approved_manager_of_team?

    render json: {
      error: "You are not authorised to view or manage this team's memberships"
    }, status: :forbidden
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

  def manager_of_membership_team?
    current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved" &&
      current_user.team_memberships.exists?(
        team_id: @team_membership.team_id,
        role: "manager",
        status: "approved"
      )
  end

  def team_membership_params
    params.require(:team_membership).permit(
      :role,
      :preferred_position
    )
  end
end
