require "digest"

class GooglePlaySubscriptionPurchaseClaimService
  class ClaimError < StandardError; end
  class MissingPurchaseToken < ClaimError; end
  class MissingPackageName < ClaimError; end
  class AccountMismatch < ClaimError; end
  class ExistingClaimConflict < ClaimError; end

  class << self
    def call(
      team:,
      purchase_token:,
      api_client: nil,
      package_name:
        ENV[
          "GOOGLE_PLAY_PACKAGE_NAME"
        ]
    )
      new(
        team: team,
        purchase_token:
          purchase_token,
        api_client:
          api_client,
        package_name:
          package_name
      ).call
    end
  end

  def initialize(
    team:,
    purchase_token:,
    api_client:,
    package_name:
  )
    @team =
      team

    @purchase_token =
      purchase_token
        .to_s
        .strip

    @api_client =
      api_client

    @package_name =
      package_name
        .to_s
        .strip
  end

  def call
    purchase =
      api_client!.fetch_subscription(
        package_name:
          required_package_name!,
        purchase_token:
          required_purchase_token!
      )

    result =
      GooglePlaySubscriptionStateMapper.call(
        decoded_notification:
          decoded_notification,
        purchase: purchase
      )

    account_token =
      verified_account_token!(
        purchase
      )

    result =
      result.merge(
        metadata:
          result
            .fetch(
              :metadata
            )
            .merge(
              "billing_account_token" =>
                account_token
            )
      )

    event =
      persist_verified_event!(
        result
      )

    StoreSubscriptionEventProcessor.call(
      event: event
    )
  end

  private

  attr_reader :team,
              :purchase_token,
              :api_client,
              :package_name

  def required_purchase_token!
    return purchase_token if
      purchase_token.present?

    raise MissingPurchaseToken,
          "Google Play purchase token is required"
  end

  def required_package_name!
    return package_name if
      package_name.present?

    raise MissingPackageName,
          "Google Play package name is not configured"
  end

  def api_client!
    api_client ||
      GooglePlayDeveloperApiClient.new
  end

  def decoded_notification
    {
      kind: "subscription",

      notification_type: 4,

      purchase_token:
        required_purchase_token!,

      package_name:
        required_package_name!,

      event_time:
        Time.current
    }
  end

  def verified_account_token!(purchase)
    token =
      StoreSubscriptionAccountToken.call(
        provider: "google_play",
        payload: purchase
      )

    unless token.present? &&
           token ==
             team.billing_account_token
      raise AccountMismatch,
            "Google Play purchase does not belong to this team"
    end

    token

  rescue StoreSubscriptionAccountToken::
           InvalidPayload,
         StoreSubscriptionAccountToken::
           InvalidToken => error

    raise AccountMismatch,
          error.message
  end

  def provider_event_id
    fingerprint =
      Digest::SHA256.hexdigest(
        required_purchase_token!
      )

    "google-play-client-claim-#{fingerprint}"
  end

  def persist_verified_event!(result)
    event =
      StoreSubscriptionEvent.find_or_initialize_by(
        provider: "google_play",
        provider_event_id:
          provider_event_id
      )

    if event.new_record?
      event.assign_attributes(
        event_type:
          result.fetch(
            :event_type
          ),

        environment:
          result.fetch(
            :environment
          ),

        provider_subscription_id:
          result[
            :provider_subscription_id
          ],

        occurred_at:
          result[
            :occurred_at
          ],

        metadata:
          result.fetch(
            :metadata
          ),

        raw_payload: {
          "source" =>
            "mobile_purchase_claim",

          "package_name" =>
            required_package_name!,

          "purchase_token_fingerprint" =>
            Digest::SHA256.hexdigest(
              required_purchase_token!
            )
        }
      )

      event.save!
    else
      validate_existing_event!(
        event
      )
    end

    event.mark_verified! unless
      event.verified?

    event
  end

  def validate_existing_event!(event)
    if event.provider_subscription_id !=
       required_purchase_token!

      raise ExistingClaimConflict,
            "Google Play claim identifier conflicts with an existing event"
    end

    if event.team_id.present? &&
       event.team_id !=
         team.id

      raise ExistingClaimConflict,
            "Google Play purchase is already linked to another team"
    end

    existing_token =
      event
        .metadata[
          "billing_account_token"
        ]
        .to_s
        .strip

    return if
      existing_token.blank? ||
      existing_token ==
        team.billing_account_token

    raise ExistingClaimConflict,
          "Google Play purchase account identity has changed"
  end
end
