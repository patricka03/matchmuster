require "test_helper"

class AppleStoreNotificationDecoderTest <
    ActiveSupport::TestCase
  class FakeSignedDataVerifier
    attr_reader :calls

    def initialize(
      notification:,
      transaction: {},
      renewal_info: {},
      error: nil
    )
      @notification = notification
      @transaction = transaction
      @renewal_info = renewal_info
      @error = error
      @calls = []
    end

    def verify_notification(payload)
      @calls << [
        :notification,
        payload
      ]

      raise @error if @error

      @notification
    end

    def verify_transaction(payload)
      @calls << [
        :transaction,
        payload
      ]

      @transaction
    end

    def verify_renewal_info(payload)
      @calls << [
        :renewal_info,
        payload
      ]

      @renewal_info
    end
  end

  setup do
    @signed_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @signed_date =
      (
        @signed_at.to_f *
        1000
      ).to_i.to_s
  end

  test "verifies and normalizes complete notification" do
    verifier =
      FakeSignedDataVerifier.new(
        notification:
          complete_notification,
        transaction: {
          "originalTransactionId" =>
            "apple-original-transaction",
          "productId" =>
            "matchmuster_plus_monthly"
        },
        renewal_info: {
          "autoRenewStatus" => 1
        }
      )

    result =
      decode(
        verifier
      )

    assert_equal(
      "SUBSCRIBED",
      result.fetch(
        :notification_type
      )
    )

    assert_equal(
      "INITIAL_BUY",
      result.fetch(
        :subtype
      )
    )

    assert_equal(
      "apple-notification-uuid",
      result.fetch(
        :notification_uuid
      )
    )

    assert_equal(
      @signed_at,
      result.fetch(
        :signed_at
      )
    )

    assert_equal(
      "sandbox",
      result.fetch(
        :environment
      )
    )

    assert_equal(
      "apple-original-transaction",
      result
        .fetch(
          :transaction
        )
        .fetch(
          "originalTransactionId"
        )
    )

    assert_equal(
      1,
      result
        .fetch(
          :renewal_info
        )
        .fetch(
          "autoRenewStatus"
        )
    )

    assert_equal(
      [
        [
          :notification,
          "signed-apple-notification"
        ],
        [
          :transaction,
          "signed-transaction"
        ],
        [
          :renewal_info,
          "signed-renewal-info"
        ]
      ],
      verifier.calls
    )
  end

  test "allows notification without nested payloads" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {
          "notificationType" =>
            "TEST",
          "notificationUUID" =>
            "apple-test-uuid",
          "signedDate" =>
            @signed_date,
          "data" => {
            "environment" =>
              "Production"
          }
        }
      )

    result =
      decode(
        verifier
      )

    assert_equal(
      "production",
      result.fetch(
        :environment
      )
    )

    assert_nil(
      result[
        :transaction
      ]
    )

    assert_nil(
      result[
        :renewal_info
      ]
    )

    assert_equal(
      1,
      verifier.calls.length
    )
  end

  test "rejects missing signed payload" do
    event =
      apple_event(
        raw_payload: {}
      )

    verifier =
      FakeSignedDataVerifier.new(
        notification: {}
      )

    error =
      assert_raises(
        AppleStoreNotificationDecoder::
          InvalidNotification
      ) do
        AppleStoreNotificationDecoder.call(
          event: event,
          signed_data_verifier:
            verifier
        )
      end

    assert_includes(
      error.message,
      "signed notification payload is missing"
    )
  end

  test "rejects non object verified notification" do
    verifier =
      FakeSignedDataVerifier.new(
        notification:
          "invalid-notification"
      )

    assert_raises(
      AppleStoreNotificationDecoder::
        InvalidNotification
    ) do
      decode(
        verifier
      )
    end
  end

  test "rejects missing notification type" do
    notification =
      complete_notification

    notification.delete(
      "notificationType"
    )

    verifier =
      FakeSignedDataVerifier.new(
        notification:
          notification
      )

    error =
      assert_raises(
        AppleStoreNotificationDecoder::
          InvalidNotification
      ) do
        decode(
          verifier
        )
      end

    assert_includes(
      error.message,
      "notification type is missing"
    )
  end

  test "rejects invalid signed date" do
    notification =
      complete_notification

    notification[
      "signedDate"
    ] =
      "not-a-timestamp"

    verifier =
      FakeSignedDataVerifier.new(
        notification:
          notification
      )

    error =
      assert_raises(
        AppleStoreNotificationDecoder::
          InvalidNotification
      ) do
        decode(
          verifier
        )
      end

    assert_includes(
      error.message,
      "signed date is invalid"
    )
  end

  test "rejects invalid environment" do
    notification =
      complete_notification

    notification[
      "data"
    ][
      "environment"
    ] =
      "Unknown"

    verifier =
      FakeSignedDataVerifier.new(
        notification:
          notification
      )

    error =
      assert_raises(
        AppleStoreNotificationDecoder::
          InvalidNotification
      ) do
        decode(
          verifier
        )
      end

    assert_includes(
      error.message,
      "environment is invalid"
    )
  end

  test "does not hide signature verification errors" do
    verifier =
      FakeSignedDataVerifier.new(
        notification: {},
        error:
          RuntimeError.new(
            "signature verification failed"
          )
      )

    error =
      assert_raises(
        RuntimeError
      ) do
        decode(
          verifier
        )
      end

    assert_equal(
      "signature verification failed",
      error.message
    )
  end

  private

  def decode(verifier)
    AppleStoreNotificationDecoder.call(
      event:
        apple_event,
      signed_data_verifier:
        verifier
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
        "apple-decoder-event",
      event_type:
        "notification_received",
      environment: "sandbox",
      metadata: {},
      raw_payload:
        raw_payload
    )
  end

  def complete_notification
    {
      "notificationType" =>
        "SUBSCRIBED",

      "subtype" =>
        "INITIAL_BUY",

      "notificationUUID" =>
        "apple-notification-uuid",

      "signedDate" =>
        @signed_date,

      "data" => {
        "environment" =>
          "Sandbox",

        "signedTransactionInfo" =>
          "signed-transaction",

        "signedRenewalInfo" =>
          "signed-renewal-info"
      }
    }
  end
end
