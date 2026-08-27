class TeamSubscriptionsController <
  ApplicationController

  before_action :authenticate_user!
  before_action :set_team
  before_action :require_team_owner!
  before_action :require_primary_subscription_team!

  def show
    render json: {
      team_id: @team.id,

      billing_account_token:
        @team.billing_account_token,

      subscription:
        TeamSubscriptionResponse.call(
          team: @team
        ),

      products:
        product_catalog_response,

      plus_features:
        plus_features_response
    }, status: :ok
  end

  private

  def set_team
    @team =
      Team.find(
        params[
          :team_id
        ]
      )

  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "Team not found"
    }, status: :not_found
  end

  def require_team_owner!
    allowed =
      current_user.account_type ==
        "manager" &&
      current_user
        .manager_verification_status ==
        "approved" &&
      @team.owned_by?(
        current_user
      )

    return if allowed

    render json: {
      error:
        "Only the team owner can manage this subscription."
    }, status: :forbidden
  end

  def require_primary_subscription_team!
    access =
      MultiTeamOwnerAccess.new(
        manager: current_user
      )

    return if access.primary_team?(
      @team
    )

    primary_team =
      access.primary_owned_team

    render json: {
      error:
        "MatchMuster Plus is managed through your primary team.",
      code:
        "subscription_primary_team_required",
      subscription_team:
        primary_team && {
          id: primary_team.id,
          name: primary_team.name
        }
    }, status: :forbidden
  end

  def product_catalog_response
    {
      monthly: {
        google_play:
          BillingProductCatalog.details(
            provider:
              "google_play",
            billing_period:
              "monthly"
          ),

        apple:
          BillingProductCatalog.details(
            provider:
              "apple",
            billing_period:
              "monthly"
          )
      },

      annual: {
        google_play:
          BillingProductCatalog.details(
            provider:
              "google_play",
            billing_period:
              "annual"
          ),

        apple:
          BillingProductCatalog.details(
            provider:
              "apple",
            billing_period:
              "annual"
          )
      }
    }
  end

  def plus_features_response
    PlusAccess.feature_states(
      team: @team
    )
  end
end
