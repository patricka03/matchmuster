class TeamSubscriptionRestoreService
  class RestoreError < StandardError; end
  class MissingTeam < RestoreError; end
  class UnsupportedProvider < RestoreError; end
  class MissingPurchaseData < RestoreError; end

  PROVIDERS = %w[
    google_play
    apple
  ].freeze

  class << self
    def call(
      team:,
      provider:,
      purchase_token: nil,
      signed_transaction: nil,
      google_play_claim_service:
        GooglePlaySubscriptionPurchaseClaimService,
      apple_claim_service:
        AppleSubscriptionPurchaseClaimService
    )
      new(
        team: team,
        provider: provider,
        purchase_token:
          purchase_token,
        signed_transaction:
          signed_transaction,
        google_play_claim_service:
          google_play_claim_service,
        apple_claim_service:
          apple_claim_service
      ).call
    end
  end

  def initialize(
    team:,
    provider:,
    purchase_token:,
    signed_transaction:,
    google_play_claim_service:,
    apple_claim_service:
  )
    @team =
      team

    @provider =
      provider
        .to_s
        .strip

    @purchase_token =
      purchase_token
        .to_s
        .strip

    @signed_transaction =
      signed_transaction
        .to_s
        .strip

    @google_play_claim_service =
      google_play_claim_service

    @apple_claim_service =
      apple_claim_service
  end

  def call
    validate_team!
    validate_provider!

    case provider
    when "google_play"
      restore_google_play

    when "apple"
      restore_apple
    end
  end

  private

  attr_reader :team,
              :provider,
              :purchase_token,
              :signed_transaction,
              :google_play_claim_service,
              :apple_claim_service

  def validate_team!
    return if
      team.present?

    raise MissingTeam,
          "Team is required to restore a subscription"
  end

  def validate_provider!
    return if
      PROVIDERS.include?(
        provider
      )

    raise UnsupportedProvider,
          "Unsupported subscription provider: #{provider}"
  end

  def restore_google_play
    if purchase_token.blank?
      raise MissingPurchaseData,
            "Google Play purchase token is required"
    end

    google_play_claim_service.call(
      team: team,
      purchase_token:
        purchase_token
    )
  end

  def restore_apple
    if signed_transaction.blank?
      raise MissingPurchaseData,
            "Apple signed transaction is required"
    end

    apple_claim_service.call(
      team: team,
      signed_transaction:
        signed_transaction
    )
  end
end
