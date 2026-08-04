class TeamsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team,
                only: %i[show update destroy stripe_connect stripe_status]
  before_action :require_manager!, only: %i[create]
  before_action :require_team_manager!,
                only: %i[update destroy stripe_connect stripe_status]

  def index
    teams = current_user.teams

    response = teams.map do |team|
      team_data = {
        id: team.id,
        name: team.name,
        description: team.description
      }

      membership = team.team_memberships.find_by(
        user: current_user,
        role: "manager",
        status: "approved"
      )

      if current_user.account_type == "manager" && membership.present?
        team_data[:invite_code] = team.invite_code
      end

      team_data
    end

    render json: response, status: :ok
  end

  def show
    render json: @team, status: :ok
  end

  def create
    @team = Team.new(team_params)

    ActiveRecord::Base.transaction do
      @team.save!

      TeamMembership.create!(
        user: current_user,
        team: @team,
        role: "manager",
        status: "approved",
        preferred_position: "CM"
      )
    end

    render json: @team, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: {
      errors: error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def update
    if @team.update(team_params)
      render json: @team, status: :ok
    else
      render json: {
        errors: @team.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @team.destroy!

    render json: {
      message: "Team deleted successfully"
    }, status: :ok
  end

  def stripe_connect
    if @team.stripe_account_id.blank?
      stripe_account = Stripe::Account.create(
        type: "express",
        country: "GB",
        email: current_user.email,
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true }
        },
        metadata: {
          team_id: @team.id
        }
      )

      @team.update!(stripe_account_id: stripe_account.id)
    end

    account_link = Stripe::AccountLink.create(
      account: @team.stripe_account_id,
      refresh_url: "http://localhost:5173/teams/#{@team.id}/stripe/refresh",
      return_url: "http://localhost:5173/teams/#{@team.id}/stripe/return",
      type: "account_onboarding"
    )

    render json: {
      onboarding_url: account_link.url
    }, status: :ok
  rescue Stripe::StripeError => error
    render json: {
      error: error.message
    }, status: :unprocessable_entity
  end

  def stripe_status
    if @team.stripe_account_id.blank?
      return render json: {
        connected: false,
        charges_enabled: false,
        payouts_enabled: false,
        details_submitted: false
      }, status: :ok
    end

    stripe_account = Stripe::Account.retrieve(@team.stripe_account_id)

    render json: {
      connected: true,
      charges_enabled: stripe_account.charges_enabled,
      payouts_enabled: stripe_account.payouts_enabled,
      details_submitted: stripe_account.details_submitted,
      disabled_reason: stripe_account.requirements.disabled_reason,
      currently_due: stripe_account.requirements.currently_due,
      pending_verification: stripe_account.requirements.pending_verification
    }, status: :ok
  rescue Stripe::StripeError => error
    render json: {
      error: error.message
    }, status: :unprocessable_entity
  end

  private

  def set_team
    @team = Team.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Team not found"
    }, status: :not_found
  end

  def team_params
    params.require(:team).permit(:name, :invite_code, :description)
  end

  def require_manager!
    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved"

    render json: {
      error: "Only approved managers can create teams."
    }, status: :forbidden
  end

  def require_team_manager!
    membership = @team.team_memberships.find_by(
      user: current_user,
      role: "manager",
      status: "approved"
    )

    return if membership

    render json: {
      error: "Only the managers of this team can edit or delete this team."
    }, status: :forbidden
  end
end
