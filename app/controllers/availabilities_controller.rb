class AvailabilitiesController < ApplicationController
  before_action :set_match, only: %i[index create]
  before_action :set_availability, only: %i[update]
  before_action :approved_player, only: %i[create update]

  def index
    availabilities = @match.availabilities

    render json: availabilities, status: :ok
  end

  def create
    @availability = @match.availabilities.new(availability_params)
    @availability.user = current_user

    if @availability.save
      render json: @availability, status: :created
    else
      render json: { errors: @availability.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def update
    if @availability.update(availability_params)
      render json: @availability, status: :ok
    else
      render json: { errors: @availability.errors.full_messages },
             status: :unprocessable_entity
    end
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

  def availability_params
    params.require(:availability).permit(:status)
  end
end
