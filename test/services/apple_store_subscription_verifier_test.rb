require "test_helper"

class AppleStoreSubscriptionVerifierTest <
    ActiveSupport::TestCase
  class FakeSignedDataVerifier
    def initialize(
      notification:,
      transaction: nil,
      renewal_info: nil,
      error: nil
    )
      @notification =
        notification

      @transaction =
        transaction

      @renewal_info =
        renewal_info

      @error =
        error
    end

    def verify_notification(
      _signed_payload
    )
      raise @error if @error

      @notification
    end

    def verify_transaction(
      _signed_payload
    )
      @transaction
    end

    def verify_renewal_info(
      _signed_payload
    )
      @renewal_info
    end
  end

  setup do
    @signed_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @starts_at =
      @signed_at - 1.hour

    @ends_at =
      @starts_at + 1.month
  end

  test "normalizes verified Apple activation" do
    result =
      verify(
        verifier:
          valid_signed_data_verifier
      )

    assert_equal(
      "subscription_activated",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      "apple-original-transaction",
      result.fetch(
        :provider_subscription_id
      )
    )

    assert_equal(
      "sandbox",
      result.fetch(
        :environment
      )
    )

    metadata =
      result.fetch(
        :metadata
      )

    assert_equal(
      "monthly",
      metadata.fetch(
        "billing_period"
      )
    )

    assert_equal(
      "matchmuster_plus_monthly",
      metadata.fetch(
        "product_id"
      )
    )

    assert_equal(
      true,
      metadata.fetch(
        "auto_renews"
      )
    )
  end

  test "safely normalizes Apple test notification" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {
          "notificationType" =>
            "TEST",

          "notificationUUID" =>
            "apple-test-notification",

          "signedDate" =>
            milliseconds(
              @signed_at
            ),

          "data" => {
            "bundleId" =>
              "uk.matchmuster.app",

            "environment" =>
              "Sandbox"
          }
        }
      )

    result =
      verify(
        verifier: verifier
      )

    assert_equal(
      "apple_test",
      result.fetch(
        :event_type
      )
    )

    assert_nil(
      result[
        :provider_subscription_id
      ]
    )
  end

  test "permanently rejects malformed notification" do
    event =
      apple_event(
        raw_payload: {}
      )

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        event: event,
        verifier:
          valid_signed_data_verifier
      )
    end
  end

  test "permanently rejects unknown Apple product" do
    transaction =
      valid_transaction

    transaction[
      "productId"
    ] =
      "another-application-product"

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        verifier:
          valid_signed_data_verifier(
            transaction:
              transaction
          )
      )
    end
  end

  test "permanently rejects incorrect application identity" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {},
        error:
          AppleSignedDataVerifier::
            InvalidAppIdentifier.new(
              "Apple bundle ID does not match"
            )
      )

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        verifier: verifier
      )
    end
  end

  test "permanently rejects invalid JWS signature" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {},
        error:
          AppleJwsVerifier::
            InvalidSignature.new(
              "Apple signature is invalid"
            )
      )

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        verifier: verifier
      )
    end
  end

  test "permanently rejects untrusted certificate chain" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {},
        error:
          AppleCertificateChainVerifier::
            UntrustedCertificateChain.new(
              "Apple certificate chain is not trusted"
            )
      )

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        verifier: verifier
      )
    end
  end

  test "configuration failure is retryable" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {},
        error:
          AppleSignedDataVerifier::
            ConfigurationError.new(
              "Apple bundle ID is not configured"
            )
      )

    error =
      assert_raises(
        StoreSubscriptionEventVerificationService::
          TemporaryFailure
      ) do
        verify(
          verifier: verifier
        )
      end

    assert_includes(
      error.message,
      "bundle ID is not configured"
    )
  end

  private

  def verify(
    event: apple_event,
    verifier:
  )
    AppleStoreSubscriptionVerifier
      .new(
        signed_data_verifier:
          verifier
      )
      .call(
        event: event
      )
  end

  def apple_event(
    raw_payload: {
      "signedPayload" =>
        "signed-apple-notification"
    }
  )
    StoreSubscriptionEvent.new(
      provider: "apple",
      provider_event_id:
        "apple-verifier-event",
      event_type:
        "notification_received",
      environment: "sandbox",
      metadata: {},
      raw_payload:
        raw_payload
    )
  end

  def valid_signed_data_verifier(
    transaction:
      valid_transaction
  )
    FakeSignedDataVerifier.new(
      notification:
        valid_notification,
      transaction:
        transaction,
      renewal_info: {
        "environment" =>
          "Sandbox",
        "autoRenewStatus" => 1
      }
    )
  end

  def valid_notification
    {
      "notificationType" =>
        "SUBSCRIBED",

      "subtype" =>
        "INITIAL_BUY",

      "notificationUUID" =>
        "apple-notification-uuid",

      "signedDate" =>
        milliseconds(
          @signed_at
        ),

      "data" => {
        "bundleId" =>
          "uk.matchmuster.app",

        "environment" =>
          "Sandbox",

        "signedTransactionInfo" =>
          "signed-transaction",

        "signedRenewalInfo" =>
          "signed-renewal-information"
      }
    }
  end

  def valid_transaction
    {
      "bundleId" =>
        "uk.matchmuster.app",

      "environment" =>
        "Sandbox",

      "originalTransactionId" =>
        "apple-original-transaction",

      "productId" =>
        "matchmuster_plus_monthly",

      "type" =>
        "Auto-Renewable Subscription",

      "purchaseDate" =>
        milliseconds(
          @starts_at
        ),

      "expiresDate" =>
        milliseconds(
          @ends_at
        )
    }
  end

  def milliseconds(time)
    (
      time.to_f *
      1000
    ).to_i
  end
end
