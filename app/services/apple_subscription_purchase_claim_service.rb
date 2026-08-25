require "digest"

class AppleSubscriptionPurchaseClaimService
  class ClaimError < StandardError; end
  class MissingSignedTransaction < ClaimError; end
  class MissingTransactionId < ClaimError; end
  class MissingSubscriptionId < ClaimError; end
  class AccountMismatch < ClaimError; end
  class ExpiredPurchase < ClaimError; end
  class RevokedPurchase < ClaimError; end
  class ExistingClaimConflict < ClaimError; end

  class << self
    def call(
      team:,
      signed_transaction:,
      signed_data_verifier: nil
    )
      new(
        team: team,
        signed_transaction:
          signed_transaction,
        signed_data_verifier:
          signed_data_verifier
      ).call
    end
  end

  def initialize(
    team:,
    signed_transaction:,
    signed_data_verifier:
  )
    @team =
      team

    @signed_transaction =
      signed_transaction
        .to_s
        .strip

    @signed_data_verifier =
      signed_data_verifier
  end

  def call
    transaction =
      signed_data_verifier!
        .verify_transaction(
          required_signed_transaction!
        )
        .deep_stringify_keys

    validate_active_purchase!(
      transaction
    )

    account_token =
      verified_account_token!(
        transaction
      )

    result =
      mapped_result(
        transaction: transaction,
        account_token:
          account_token
      )

    event =
      persist_verified_event!(
        result: result,
        transaction: transaction
      )

    StoreSubscriptionEventProcessor.call(
      event: event
    )
  end

  private

  attr_reader :team,
              :signed_transaction,
              :signed_data_verifier

  def required_signed_transaction!
    return signed_transaction if
      signed_transaction.present?

    raise MissingSignedTransaction,
          "Apple signed transaction is required"
  end

  def signed_data_verifier!
    signed_data_verifier ||
      AppleSignedDataVerifierFactory.build
  end

  def validate_active_purchase!(transaction)
    if transaction[
      "revocationDate"
    ].present?
      raise RevokedPurchase,
            "Apple subscription purchase has been revoked"
    end

    return if
      expiry_time!(
        transaction
      ) >
        Time.current

    raise ExpiredPurchase,
          "Apple subscription purchase has expired"
  end

  def verified_account_token!(transaction)
    token =
      StoreSubscriptionAccountToken.call(
        provider: "apple",
        payload: transaction
      )

    unless token.present? &&
           token ==
             team.billing_account_token
      raise AccountMismatch,
            "Apple purchase does not belong to this team"
    end

    token

  rescue StoreSubscriptionAccountToken::
           InvalidPayload,
         StoreSubscriptionAccountToken::
           InvalidToken => error

    raise AccountMismatch,
          error.message
  end

  def mapped_result(
    transaction:,
    account_token:
  )
    result =
      AppleSubscriptionStateMapper.call(
        decoded_notification: {
          notification_type:
            "SUBSCRIBED",

          subtype:
            "INITIAL_BUY",

          environment:
            normalized_environment!(
              transaction
            ),

          signed_at:
            signed_time!(
              transaction
            ),

          transaction:
            transaction,

          renewal_info: {
            "autoRenewStatus" => 1
          }
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
              account_token
          )
    )
  end

  def normalized_environment!(transaction)
    environment =
      transaction[
        "environment"
      ]
        .to_s
        .strip
        .downcase

    return environment if
      StoreSubscriptionEvent::
        ENVIRONMENTS.include?(
          environment
        )

    raise AppleSubscriptionStateMapper::
            InvalidPurchase,
          "Apple subscription environment is invalid"
  end

  def signed_time!(transaction)
    value =
      transaction[
        "signedDate"
      ].presence ||
        transaction[
          "purchaseDate"
        ]

    time_from_milliseconds!(
      value,
      field: "signed date"
    )
  end

  def expiry_time!(transaction)
    time_from_milliseconds!(
      transaction[
        "expiresDate"
      ],
      field: "expiry date"
    )
  end

  def time_from_milliseconds!(
    value,
    field:
  )
    milliseconds =
      value
        .to_s
        .strip

    unless milliseconds.match?(
      /\A\d+\z/
    )
      raise AppleSubscriptionStateMapper::
              InvalidPurchase,
            "Apple subscription #{field} is invalid"
    end

    Time.zone.at(
      milliseconds.to_i /
        1000.0
    )
  end

  def transaction_id!(transaction)
    transaction_id =
      transaction[
        "transactionId"
      ]
        .to_s
        .strip

    return transaction_id if
      transaction_id.present?

    raise MissingTransactionId,
          "Apple transaction ID is missing"
  end

  def subscription_id!(transaction)
    subscription_id =
      transaction[
        "originalTransactionId"
      ]
        .to_s
        .strip

    return subscription_id if
      subscription_id.present?

    raise MissingSubscriptionId,
          "Apple original transaction ID is missing"
  end

  def provider_event_id(transaction)
    fingerprint =
      Digest::SHA256.hexdigest(
        transaction_id!(
          transaction
        )
      )

    "apple-client-claim-#{fingerprint}"
  end

  def persist_verified_event!(
    result:,
    transaction:
  )
    event =
      StoreSubscriptionEvent.find_or_initialize_by(
        provider: "apple",
        provider_event_id:
          provider_event_id(
            transaction
          )
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

          "transaction_id" =>
            transaction_id!(
              transaction
            ),

          "signed_transaction_fingerprint" =>
            Digest::SHA256.hexdigest(
              required_signed_transaction!
            )
        }
      )

      event.save!
    else
      validate_existing_event!(
        event: event,
        result: result,
        transaction: transaction
      )
    end

    event.mark_verified! unless
      event.verified?

    event
  end

  def validate_existing_event!(
    event:,
    result:,
    transaction:
  )
    expected_subscription_id =
      subscription_id!(
        transaction
      )

    if event.provider_subscription_id !=
       expected_subscription_id
      raise ExistingClaimConflict,
            "Apple claim identifier conflicts with an existing event"
    end

    if event.provider_subscription_id !=
       result[
         :provider_subscription_id
       ]
      raise ExistingClaimConflict,
            "Apple claim subscription identity has changed"
    end

    if event.team_id.present? &&
       event.team_id !=
         team.id
      raise ExistingClaimConflict,
            "Apple purchase is already linked to another team"
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
          "Apple purchase account identity has changed"
  end
end
