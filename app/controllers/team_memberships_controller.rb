class TeamMembershipsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_team_membership,
                only: %i[approve reject destroy]

  before_action :authorize_manager!,
                only: %i[approve reject]

  def index
    @team = Team.find(params[:team_id])

    @team_memberships = @team.team_memberships.includes(:user)

    render json: @team_memberships.as_json(
      include: {
        user: {
          only: %i[id first_name last_name email]
        }
      }
    )
  end

  def create
    @team = Team.find(params[:team_id])

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
    @team_membership.update!(status: "approved")

    render json: @team_membership
  end

  def reject
    @team_membership.update!(status: "rejected")

    render json: @team_membership
  end

  def destroy
    if @team_membership.user == current_user || manager_of_team?
      @team_membership.destroy
      head :no_content
    else
      render json: {
        error: "You are not authorised to remove this membership"
      }, status: :forbidden
    end
  end

  private

  def set_team_membership
    @team_membership = TeamMembership.find(params[:id])
  end

  def authorize_manager!
    return if manager_of_team?

    render json: {
      error: "You are not authorised to perform this action"
    }, status: :forbidden
  end

  def manager_of_team?
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
