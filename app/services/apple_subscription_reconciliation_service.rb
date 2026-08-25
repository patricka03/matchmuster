require "digest"
require "json"

class AppleSubscriptionReconciliationService
  ACTIVE_STATUS = 1
  EXPIRED_STATUS = 2
  BILLING_RETRY_STATUS = 3
  GRACE_PERIOD_STATUS = 4
  REVOKED_STATUS = 5

  class ReconciliationError < StandardError; end
  class InvalidEntitlement < ReconciliationError; end
  class InvalidConfiguration < ReconciliationError; end
  class InvalidResponse < ReconciliationError; end
  class AccountMismatch < ReconciliationError; end
  class SubscriptionNotFound < ReconciliationError; end
  class TemporaryFailure < ReconciliationError; end
  class ExistingReconciliationConflict < ReconciliationError; end

  class << self
    def call(
      entitlement:,
      api_client: nil,
      signed_data_verifier: nil,
      checked_at: Time.current
    )
      new(
        entitlement: entitlement,
        api_client: api_client,
        signed_data_verifier:
          signed_data_verifier,
        checked_at: checked_at
      ).call
    end
  end

  def initialize(
    entitlement:,
    api_client:,
    signed_data_verifier:,
    checked_at:
  )
    @entitlement = entitlement
    @api_client = api_client
    @signed_data_verifier =
      signed_data_verifier
    @checked_at = checked_at
  end

  def call
    validate_entitlement!

    reconciliation_time =
      normalized_checked_at!

    response =
      api_client!
        .fetch_subscription_status(
          original_transaction_id:
            required_subscription_id!
        )

    unless response.is_a?(
      Hash
    )
      raise InvalidResponse,
            "Apple subscription status response must be an object"
    end

    response =
      response.deep_stringify_keys

    status_item =
      matching_status_item!(
        response
      )

    transaction =
      signed_data_verifier!
        .verify_transaction(
          required_signed_value!(
            status_item,
            "signedTransactionInfo"
          )
        )
        .deep_stringify_keys

    renewal_info =
      signed_data_verifier!
        .verify_renewal_info(
          required_signed_value!(
            status_item,
            "signedRenewalInfo"
          )
        )
        .deep_stringify_keys

    validate_verified_identity!(
      response: response,
      status_item: status_item,
      transaction: transaction,
      renewal_info: renewal_info
    )

    account_token =
      verified_account_token!(
        transaction
      )

    result =
      mapped_result(
        status_item: status_item,
        transaction: transaction,
        renewal_info: renewal_info,
        account_token: account_token,
        checked_at: reconciliation_time
      )

    event =
      persist_verified_event!(
        result: result,
        status_item: status_item
      )

    StoreSubscriptionEventProcessor.call(
      event: event
    )

  rescue AppleAppStoreServerApiClient::NotFound => error
    raise SubscriptionNotFound,
          error.message

  rescue AppleAppStoreServerApiClient::ConfigurationError,
         AppleSignedDataVerifier::ConfigurationError,
         AppleCertificateChainVerifier::ConfigurationError => error
    raise InvalidConfiguration,
          error.message

  rescue AppleAppStoreServerApiClient::AuthenticationError,
         AppleAppStoreServerApiClient::RateLimited,
         AppleAppStoreServerApiClient::RequestFailed => error
    raise TemporaryFailure,
          error.message

  rescue AppleSignedDataVerifier::InvalidPayload,
         AppleSignedDataVerifier::InvalidAppIdentifier,
         AppleSignedDataVerifier::InvalidEnvironment,
         AppleJwsVerifier::VerificationError,
         AppleCertificateChainVerifier::InvalidCertificate,
         AppleCertificateChainVerifier::InvalidCertificatePurpose,
         AppleCertificateChainVerifier::UntrustedCertificateChain,
         AppleSubscriptionStateMapper::InvalidPurchase => error
    raise InvalidResponse,
          error.message
  end

  private

  attr_reader :entitlement,
              :api_client,
              :signed_data_verifier,
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
        "apple"

    raise InvalidEntitlement,
          "Entitlement is not linked to Apple"
  end

  def required_subscription_id!
    subscription_id =
      entitlement
        .provider_subscription_id
        .to_s
        .strip

    return subscription_id if
      subscription_id.present?

    raise InvalidEntitlement,
          "Apple entitlement is missing its original transaction ID"
  end

  def api_client!
    api_client ||
      AppleAppStoreServerApiClient.new
  end

  def signed_data_verifier!
    @signed_data_verifier ||=
      AppleSignedDataVerifierFactory.build
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

  def matching_status_item!(response)
    data =
      response[
        "data"
      ]

    unless data.is_a?(
      Array
    )
      raise InvalidResponse,
            "Apple subscription status data is missing"
    end

    status_items =
      data.flat_map do |group|
        next [] unless
          group.is_a?(
            Hash
          )

        items =
          group.deep_stringify_keys[
            "lastTransactions"
          ]

        items.is_a?(
          Array
        ) ? items : []
      end

    status_item =
      status_items.find do |item|
        item.is_a?(
          Hash
        ) &&
          item
            .deep_stringify_keys[
              "originalTransactionId"
            ]
            .to_s
            .strip ==
              required_subscription_id!
      end

    return status_item.deep_stringify_keys if
      status_item

    raise SubscriptionNotFound,
          "Apple subscription status does not contain the linked transaction"
  end

  def required_signed_value!(
    status_item,
    key
  )
    value =
      status_item[
        key
      ]
        .to_s
        .strip

    return value if
      value.present?

    raise InvalidResponse,
          "Apple subscription status is missing #{key}"
  end

  def validate_verified_identity!(
    response:,
    status_item:,
    transaction:,
    renewal_info:
  )
    identifiers = [
      status_item[
        "originalTransactionId"
      ],
      transaction[
        "originalTransactionId"
      ],
      renewal_info[
        "originalTransactionId"
      ]
    ].map do |value|
      value
        .to_s
        .strip
    end

    identifiers_match =
      identifiers.all? do |value|
        value ==
          required_subscription_id!
      end

    unless identifiers_match
      raise InvalidResponse,
            "Apple subscription identifiers do not match"
    end

    response_bundle_id =
      response[
        "bundleId"
      ]
        .to_s
        .strip

    transaction_bundle_id =
      transaction[
        "bundleId"
      ]
        .to_s
        .strip

    unless response_bundle_id.present? &&
           response_bundle_id ==
             transaction_bundle_id
      raise InvalidResponse,
            "Apple subscription bundle IDs do not match"
    end

    response_environment =
      normalized_environment(
        response[
          "environment"
        ]
      )

    transaction_environment =
      normalized_environment(
        transaction[
          "environment"
        ]
      )

    renewal_environment =
      normalized_environment(
        renewal_info[
          "environment"
        ]
      )

    unless response_environment ==
           transaction_environment &&
           response_environment ==
             renewal_environment
      raise InvalidResponse,
            "Apple subscription environments do not match"
    end
  end

  def normalized_environment(value)
    environment =
      value
        .to_s
        .strip
        .downcase

    return environment if
      StoreSubscriptionEvent::
        ENVIRONMENTS.include?(
          environment
        )

    raise InvalidResponse,
          "Apple subscription environment is invalid"
  end

  def verified_account_token!(transaction)
    token =
      StoreSubscriptionAccountToken.call(
        provider: "apple",
        payload: transaction
      )

    unless token.present? &&
           token ==
             entitlement
               .team
               .billing_account_token
      raise AccountMismatch,
            "Apple subscription does not belong to this team"
    end

    token

  rescue StoreSubscriptionAccountToken::InvalidPayload,
         StoreSubscriptionAccountToken::InvalidToken => error
    raise AccountMismatch,
          error.message
  end

  def mapped_result(
    status_item:,
    transaction:,
    renewal_info:,
    account_token:,
    checked_at:
  )
    lifecycle =
      lifecycle_for!(
        status_item: status_item,
        renewal_info: renewal_info
      )

    result =
      AppleSubscriptionStateMapper.call(
        decoded_notification: {
          notification_type:
            lifecycle.fetch(
              :notification_type
            ),
          subtype:
            lifecycle[
              :subtype
            ],
          environment:
            normalized_environment(
              transaction[
                "environment"
              ]
            ),
          signed_at:
            checked_at,
          transaction:
            transaction,
          renewal_info:
            renewal_info
        }
      )

    result.merge(
      metadata:
        result
          .fetch(
            :metadata
          )
          .merge(
            "billing_account_token" =>
              account_token,
            "apple_subscription_status" =>
              status_code!(
                status_item
              )
          )
    )
  end

  def lifecycle_for!(
    status_item:,
    renewal_info:
  )
    case status_code!(
      status_item
    )
    when ACTIVE_STATUS
      if auto_renews?(
        renewal_info
      )
        {
          notification_type:
            "DID_RENEW",
          subtype: nil
        }
      else
        {
          notification_type:
            "DID_CHANGE_RENEWAL_STATUS",
          subtype:
            "AUTO_RENEW_DISABLED"
        }
      end

    when EXPIRED_STATUS
      {
        notification_type:
          "EXPIRED",
        subtype: nil
      }

    when BILLING_RETRY_STATUS
      {
        notification_type:
          "DID_FAIL_TO_RENEW",
        subtype: nil
      }

    when GRACE_PERIOD_STATUS
      {
        notification_type:
          "DID_FAIL_TO_RENEW",
        subtype:
          "GRACE_PERIOD"
      }

    when REVOKED_STATUS
      {
        notification_type:
          "REVOKE",
        subtype: nil
      }

    else
      raise InvalidResponse,
            "Apple subscription status is unsupported"
    end
  end

  def status_code!(status_item)
    value =
      status_item[
        "status"
      ]

    status =
      Integer(
        value,
        exception: false
      )

    return status if
      [
        ACTIVE_STATUS,
        EXPIRED_STATUS,
        BILLING_RETRY_STATUS,
        GRACE_PERIOD_STATUS,
        REVOKED_STATUS
      ].include?(
        status
      )

    raise InvalidResponse,
          "Apple subscription status is invalid"
  end

  def auto_renews?(renewal_info)
    value =
      renewal_info[
        "autoRenewStatus"
      ]

    return true if
      value == 1 ||
      value == "1" ||
      value == true

    return false if
      value == 0 ||
      value == "0" ||
      value == false

    raise InvalidResponse,
          "Apple subscription auto-renewal state is invalid"
  end

  def persist_verified_event!(
    result:,
    status_item:
  )
    fingerprint =
      snapshot_fingerprint(
        status_item
      )

    event =
      StoreSubscriptionEvent.find_or_initialize_by(
        provider: "apple",
        provider_event_id:
          "apple-reconciliation-#{fingerprint}"
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
          "apple_subscription_status" =>
            status_code!(
              status_item
            ),
          "status_snapshot_fingerprint" =>
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
       required_subscription_id!
      raise ExistingReconciliationConflict,
            "Apple reconciliation identifier conflicts with an existing event"
    end

    if event.event_type !=
       result.fetch(
         :event_type
       )
      raise ExistingReconciliationConflict,
            "Apple reconciliation state conflicts with an existing event"
    end

    if event.team_id.present? &&
       event.team_id !=
         entitlement.team_id
      raise ExistingReconciliationConflict,
            "Apple reconciliation belongs to another team"
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
          "Apple reconciliation account identity has changed"
  end

  def snapshot_fingerprint(status_item)
    Digest::SHA256.hexdigest(
      [
        required_subscription_id!,
        JSON.generate(
          canonicalize(
            status_item
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
