class TeamSubscriptionClaimsController <
  ApplicationController

  before_action :authenticate_user!
  before_action :set_team
  before_action :require_team_owner!
  before_action :require_primary_subscription_team!

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
        "Only the team owner can manage this subscription.",
      code:
        "subscription_manager_required"
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
