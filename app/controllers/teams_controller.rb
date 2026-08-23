class TeamsController < ApplicationController
  before_action :authenticate_user!

  before_action :set_team, only: %i[ show update destroy stripe_connect stripe_status stripe_dashboard update_badge ]

  before_action :require_manager!, only: :create
  before_action :require_team_member!, only: :show

  before_action :require_team_manager!, only: %i[ update destroy stripe_connect stripe_status stripe_dashboard update_badge ]

  def index
    teams = Team.joins(:team_memberships).where(
              team_memberships: {
                user_id: current_user.id,
                status: "approved"
              }
            )

    if current_user.account_type == "manager"
      teams = teams.where(
        team_memberships: {
          role: "manager"
        }
      )
    end

    teams = teams.distinct

    render json: teams.map { |team| team_response(team) },
          status: :ok
  end

  def show
    render json: team_response(@team), status: :ok
  end

  def create
    @team =
      Team.new(
        team_params
      )

    ActiveRecord::Base.transaction do
      @team.save!

      TeamMembership.create!(
        user: current_user,
        team: @team,
        role: "manager",
        status: "approved",
        preferred_position: "CM"
      )

      TeamEntitlementService.start_standard_trial!(
        team: @team
      )
    end

    render json:
      team_response(@team),
      status: :created

  rescue ActiveRecord::RecordInvalid => error
    render json: {
      errors:
        error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def update
    if @team.update(team_params)
      render json: team_response(@team), status: :ok
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
          card_payments: {
            requested: true
          },
          transfers: {
            requested: true
          }
        },
        metadata: {
          team_id: @team.id
        }
      )

      @team.update!(
        stripe_account_id: stripe_account.id
      )
    end

    frontend_url =
      ENV.fetch("FRONTEND_URL", "http://localhost:5173")

    account_link = Stripe::AccountLink.create(
      account: @team.stripe_account_id,
      refresh_url:
        "#{frontend_url}/dashboard?stripe=refresh&team_id=#{@team.id}",
      return_url:
        "#{frontend_url}/dashboard?stripe=return&team_id=#{@team.id}",
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
        setup_complete: false,
        charges_enabled: false,
        payouts_enabled: false,
        details_submitted: false,
        currently_due: [],
        pending_verification: []
      }, status: :ok
    end

    stripe_account =
      Stripe::Account.retrieve(@team.stripe_account_id)

    setup_complete =
      stripe_account.details_submitted &&
      stripe_account.charges_enabled &&
      stripe_account.payouts_enabled

    render json: {
      connected: true,
      setup_complete: setup_complete,
      charges_enabled: stripe_account.charges_enabled,
      payouts_enabled: stripe_account.payouts_enabled,
      details_submitted: stripe_account.details_submitted,
      disabled_reason:
        stripe_account.requirements.disabled_reason,
      currently_due:
        stripe_account.requirements.currently_due || [],
      pending_verification:
        stripe_account.requirements.pending_verification || []
    }, status: :ok
  rescue Stripe::StripeError => error
    render json: {
      error: error.message
    }, status: :unprocessable_entity
  end

  def stripe_dashboard
    if @team.stripe_account_id.blank?
      return render json: {
        error: "This team has not connected a Stripe account."
      }, status: :unprocessable_entity
    end

    login_link =
      Stripe::Account.create_login_link(
        @team.stripe_account_id
      )

    render json: {
      dashboard_url: login_link.url
    }, status: :ok
  rescue Stripe::StripeError => error
    render json: {
      error: error.message
    }, status: :unprocessable_entity
  end

  def update_badge
    badge = params[:badge]

    if badge.blank?
      return render json: {
        error: "Please select a team badge."
      }, status: :unprocessable_entity
    end

    allowed_types = %w[
      image/jpeg
      image/png
      image/webp
    ]

    unless allowed_types.include?(badge.content_type)
      return render json: {
        error: "The badge must be a JPG, PNG or WebP image."
      }, status: :unprocessable_entity
    end

    if badge.size > 5.megabytes
      return render json: {
        error: "The badge must be smaller than 5 MB."
      }, status: :unprocessable_entity
    end

    @team.badge.attach(badge)

    render json: {
      message: "Team badge updated successfully.",
      team: team_response(@team)
    }, status: :ok
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
    params.require(:team).permit(
      :name,
      :description
    )
  end

  def approved_membership(team)
    team.team_memberships.find_by(
      user: current_user,
      status: "approved"
    )
  end

  def team_response(team)
    membership =
      approved_membership(team)

    response = {
      id: team.id,
      name: team.name,
      description: team.description,
      badge_url:
        team.badge.attached? ?
          url_for(team.badge) :
          nil,
      membership_id:
        membership&.id,
      membership_role:
        membership&.role
    }

    if current_user.account_type == "manager" &&
      membership&.role == "manager"

      response[:invite_code] =
        team.invite_code

      response[:subscription] =
        team_subscription_response(
          team
        )
    end

    response
  end

  def team_subscription_response(team)
    entitlement =
      team.team_entitlement

    unless entitlement
      return {
        plan: "free",
        status: "free",
        source: nil,
        plus_active: false,
        days_remaining: nil,
        starts_at: nil,
        ends_at: nil,
        auto_renews: false
      }
    end

    now =
      Time.current

    plus_active =
      entitlement.plus_active?(
        at: now
      )

    {
      plan:
        entitlement.effective_plan(
          at: now
        ),

      status:
        plus_active ?
          entitlement.status :
          "expired",

      source:
        entitlement.source,

      plus_active:
        plus_active,

      days_remaining:
        entitlement.days_remaining(
          at: now
        ),

      starts_at:
        entitlement.starts_at,

      ends_at:
        entitlement.ends_at,

      auto_renews:
        entitlement.auto_renews
    }
  end

  def require_manager!
    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved"

    render json: {
      error: "Only approved managers can create teams."
    }, status: :forbidden
  end

  def require_team_member!
    return if approved_membership(@team)

    render json: {
      error: "You are not an approved member of this team."
    }, status: :forbidden
  end

  def require_team_manager!
    membership = approved_membership(@team)

    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved" &&
              membership&.role == "manager"

    render json: {
      error: "Only approved team managers can manage this team."
    }, status: :forbidden
  end
end
