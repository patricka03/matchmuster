require "digest"
require "json"

class GooglePlaySubscriptionReconciliationService
  class ReconciliationError < StandardError; end
  class InvalidEntitlement < ReconciliationError; end
  class InvalidConfiguration < ReconciliationError; end
  class AccountMismatch < ReconciliationError; end
  class SubscriptionNotFound < ReconciliationError; end
  class TemporaryFailure < ReconciliationError; end

  class ExistingReconciliationConflict <
    ReconciliationError
  end

  class << self
    def call(
      entitlement:,
      api_client: nil,
      package_name:
        ENV[
          "GOOGLE_PLAY_PACKAGE_NAME"
        ],
      checked_at: Time.current
    )
      new(
        entitlement: entitlement,
        api_client: api_client,
        package_name: package_name,
        checked_at: checked_at
      ).call
    end
  end

  def initialize(
    entitlement:,
    api_client:,
    package_name:,
    checked_at:
  )
    @entitlement =
      entitlement

    @api_client =
      api_client

    @package_name =
      package_name
        .to_s
        .strip

    @checked_at =
      checked_at
  end

  def call
    validate_entitlement!

    reconciliation_time =
      normalized_checked_at!

    purchase =
      api_client!.fetch_subscription(
        package_name:
          required_package_name!,
        purchase_token:
          required_purchase_token!
      ).deep_stringify_keys

    result =
      GooglePlaySubscriptionStateMapper.call(
        decoded_notification:
          decoded_notification(
            reconciliation_time
          ),
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
        result: result,
        purchase: purchase
      )

    StoreSubscriptionEventProcessor.call(
      event: event
    )

  rescue GooglePlayDeveloperApiClient::
           NotFound => error

    raise SubscriptionNotFound,
          error.message

  rescue GooglePlayDeveloperApiClient::
           AuthenticationError,
         GooglePlayDeveloperApiClient::
           RequestFailed => error

    raise TemporaryFailure,
          error.message
  end

  private

  attr_reader :entitlement,
              :api_client,
              :package_name,
              :checked_at

  def validate_entitlement!
    unless entitlement.is_a?(
      TeamEntitlement
    ) && entitlement.persisted?
      raise InvalidEntitlement,
            "A saved team entitlement is required"
    end

    return if
      entitlement.paid? &&
      entitlement.provider ==
        "google_play"

    raise InvalidEntitlement,
          "Entitlement is not linked to Google Play"
  end

  def required_package_name!
    return package_name if
      package_name.present?

    raise InvalidConfiguration,
          "Google Play package name is not configured"
  end

  def required_purchase_token!
    purchase_token =
      entitlement
        .provider_subscription_id
        .to_s
        .strip

    return purchase_token if
      purchase_token.present?

    raise InvalidEntitlement,
          "Google Play entitlement is missing its purchase token"
  end

  def api_client!
    api_client ||
      GooglePlayDeveloperApiClient.new
  end

  def normalized_checked_at!
    return checked_at.in_time_zone if
      checked_at.respond_to?(
        :in_time_zone
      ) &&
      !checked_at.is_a?(
        String
      )

    Time.zone.iso8601(
      checked_at.to_s
    )

  rescue ArgumentError,
         TypeError

    raise ArgumentError,
          "Reconciliation time must be a valid timestamp"
  end

  def decoded_notification(
    reconciliation_time
  )
    {
      kind: "subscription",
      notification_type: 2,
      purchase_token:
        required_purchase_token!,
      package_name:
        required_package_name!,
      event_time:
        reconciliation_time
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
             entitlement
               .team
               .billing_account_token
      raise AccountMismatch,
            "Google Play subscription does not belong to this team"
    end

    token

  rescue StoreSubscriptionAccountToken::
           InvalidPayload,
         StoreSubscriptionAccountToken::
           InvalidToken => error

    raise AccountMismatch,
          error.message
  end

  def persist_verified_event!(
    result:,
    purchase:
  )
    fingerprint =
      snapshot_fingerprint(
        purchase
      )

    event =
      StoreSubscriptionEvent.find_or_initialize_by(
        provider: "google_play",
        provider_event_id:
          "google-play-reconciliation-#{fingerprint}"
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
            "scheduled_reconciliation",
          "package_name" =>
            required_package_name!,
          "purchase_snapshot_fingerprint" =>
            fingerprint
        }
      )

      event.save!
    else
      validate_existing_event!(
        event: event,
        result: result
      )
    end

    event.mark_verified! unless
      event.verified?

    event
  end

  def validate_existing_event!(
    event:,
    result:
  )
    if event.provider_subscription_id !=
       required_purchase_token!
      raise ExistingReconciliationConflict,
            "Google Play reconciliation identifier conflicts with an existing event"
    end

    if event.event_type !=
       result.fetch(
         :event_type
       )
      raise ExistingReconciliationConflict,
            "Google Play reconciliation state conflicts with an existing event"
    end

    if event.team_id.present? &&
       event.team_id !=
         entitlement.team_id
      raise ExistingReconciliationConflict,
            "Google Play reconciliation belongs to another team"
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
        entitlement
          .team
          .billing_account_token

    raise ExistingReconciliationConflict,
          "Google Play reconciliation account identity has changed"
  end

  def snapshot_fingerprint(purchase)
    Digest::SHA256.hexdigest(
      [
        required_purchase_token!,
        JSON.generate(
          canonicalize(
            purchase
          )
        )
      ].join(
        ":"
      )
    )
  end

  def canonicalize(value)
    case value
    when Hash
      value
        .deep_stringify_keys
        .sort
        .to_h
        .transform_values do |child|
          canonicalize(
            child
          )
        end

    when Array
      value.map do |child|
        canonicalize(
          child
        )
      end

    else
      value
    end
  end
end
