class TeamSubscriptionClaimsController <
  ApplicationController

  before_action :authenticate_user!
  before_action :set_team
  before_action :require_team_manager!

  rescue_from(
    ActionController::ParameterMissing,
    TeamSubscriptionRestoreService::
      RestoreError,
    with: :render_bad_request
  )

  rescue_from(
    GooglePlaySubscriptionPurchaseClaimService::
      ClaimError,
    AppleSubscriptionPurchaseClaimService::
      ClaimError,
    GooglePlayDeveloperApiClient::
      NotFound,
    GooglePlaySubscriptionStateMapper::
      InvalidPurchase,
    AppleSubscriptionStateMapper::
      InvalidPurchase,
    AppleSignedDataVerifier::
      InvalidPayload,
    AppleSignedDataVerifier::
      InvalidAppIdentifier,
    AppleSignedDataVerifier::
      InvalidEnvironment,
    AppleJwsVerifier::
      VerificationError,
    StoreSubscriptionEventProcessor::
      MissingTeam,
    StoreSubscriptionEventProcessor::
      MissingSubscriptionId,
    StoreSubscriptionEventProcessor::
      InvalidAccountToken,
    StoreSubscriptionEventProcessor::
      UnknownAccountToken,
    StoreSubscriptionEventProcessor::
      SubscriptionNotLinked,
    with: :render_unprocessable_claim
  )

  rescue_from(
    GooglePlaySubscriptionPurchaseClaimService::
      MissingPackageName,
    GooglePlayDeveloperApiClient::
      AuthenticationError,
    GooglePlayDeveloperApiClient::
      RequestFailed,
    AppleSignedDataVerifier::
      ConfigurationError,
    AppleCertificateChainVerifier::
      ConfigurationError,
    with: :render_temporary_failure
  )

  rescue_from(
    GooglePlaySubscriptionPurchaseClaimService::
      ExistingClaimConflict,
    AppleSubscriptionPurchaseClaimService::
      ExistingClaimConflict,
    StoreSubscriptionEventProcessor::
      SubscriptionOwnershipConflict,
    with: :render_claim_conflict
  )

  def google_play
    GooglePlaySubscriptionPurchaseClaimService.call(
      team: @team,
      purchase_token:
        params.require(
          :purchase_token
        )
    )

    render_subscription
  end

  def apple
    AppleSubscriptionPurchaseClaimService.call(
      team: @team,
      signed_transaction:
        params.require(
          :signed_transaction
        )
    )

    render_subscription
  end

  def restore
    TeamSubscriptionRestoreService.call(
      team: @team,
      provider:
        params.require(
          :provider
        ),
      purchase_token:
        params[
          :purchase_token
        ],
      signed_transaction:
        params[
          :signed_transaction
        ]
    )

    render_subscription
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
      error:
        "Team not found",
      code:
        "team_not_found"
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
        "Only approved team managers can manage this subscription.",
      code:
        "subscription_manager_required"
    }, status: :forbidden
  end

  def render_subscription
    render json: {
      team_id:
        @team.id,

      subscription:
        TeamSubscriptionResponse.call(
          team: @team.reload
        )
    }, status: :ok
  end

  def render_bad_request(error)
    render json: {
      error:
        error.message,
      code:
        "invalid_subscription_request"
    }, status: :bad_request
  end

  def render_unprocessable_claim(
    _error
  )
    render json: {
      error:
        "Subscription purchase could not be verified.",
      code:
        "subscription_verification_failed"
    }, status: :unprocessable_entity
  end

  def render_claim_conflict(
    _error
  )
    render json: {
      error:
        "This subscription purchase cannot be linked to this team.",
      code:
        "subscription_ownership_conflict"
    }, status: :conflict
  end

  def render_temporary_failure(
    _error
  )
    render json: {
      error:
        "Subscription verification is temporarily unavailable.",
      code:
        "subscription_verification_unavailable"
    }, status: :service_unavailable
  end
end
