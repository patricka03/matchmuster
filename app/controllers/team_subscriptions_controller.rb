class TeamSubscriptionsController <
  ApplicationController

  before_action :authenticate_user!
  before_action :set_team
  before_action :require_team_manager!

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

  def approved_membership
    @team.team_memberships.find_by(
      user: current_user,
      status: "approved"
    )
  end

  def require_team_manager!
    membership =
      approved_membership

    allowed =
      current_user.account_type ==
        "manager" &&
      current_user
        .manager_verification_status ==
        "approved" &&
      membership&.role ==
        "manager"

    return if allowed

    render json: {
      error:
        "Only approved team managers can manage this subscription."
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
