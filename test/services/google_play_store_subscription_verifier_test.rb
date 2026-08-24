require "test_helper"
require "base64"
require "json"

class GooglePlayStoreSubscriptionVerifierTest <
  ActiveSupport::TestCase

  PACKAGE_NAME =
    "uk.matchmuster.app"

  setup do
    @event_sequence = 0

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_time =
      @starts_at + 1.hour
  end

  test "verified active purchase returns normalized result" do
    event =
      subscription_event(
        notification_type: 4
      )

    calls = []

    client =
      api_client do |
        package_name,
        purchase_token
      |
        calls << {
          package_name:
            package_name,
          purchase_token:
            purchase_token
        }

        valid_purchase(
          state:
            "SUBSCRIPTION_STATE_ACTIVE"
        )
      end

    result =
      verify(
        event,
        client
      )

    assert_equal(
      "subscription_activated",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      "google-purchase-token",
      result.fetch(
        :provider_subscription_id
      )
    )

    assert_equal(
      "monthly",
      result
        .fetch(
          :metadata
        )
        .fetch(
          "billing_period"
        )
    )

    assert_equal(
      [
        {
          package_name:
            PACKAGE_NAME,
          purchase_token:
            "google-purchase-token"
        }
      ],
      calls
    )
  end

  test "test notification does not call Developer API" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            event_time_millis,
          "testNotification" => {
            "version" => "1.0"
          }
        }
      )

    result =
      verify(
        event,
        failing_client
      )

    assert_equal(
      "google_test_notification",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      "sandbox",
      result.fetch(
        :environment
      )
    )

    assert_nil(
      result[
        :provider_subscription_id
      ]
    )
  end

  test "unrelated notification is safely normalized" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            event_time_millis,
          "oneTimeProductNotification" => {
            "notificationType" => 1,
            "purchaseToken" =>
              "one-time-token",
            "sku" => "football-pack"
          }
        }
      )

    result =
      verify(
        event,
        failing_client
      )

    assert_equal(
      "google_unsupported",
      result.fetch(
        :event_type
      )
    )
  end

  test "voided subscription becomes revoked" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            event_time_millis,
          "voidedPurchaseNotification" => {
            "purchaseToken" =>
              "voided-purchase-token",
            "orderId" =>
              "GPA.1234-5678",
            "productType" => 1,
            "refundType" => 1
          }
        }
      )

    client =
      api_client do |
        _package_name,
        purchase_token
      |
        assert_equal(
          "voided-purchase-token",
          purchase_token
        )

        valid_purchase(
          state:
            "SUBSCRIPTION_STATE_EXPIRED"
        )
      end

    result =
      verify(
        event,
        client
      )

    assert_equal(
      "subscription_revoked",
      result.fetch(
        :event_type
      )
    )
  end

  test "incorrect package is permanently rejected" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            "com.fake.application",
          "eventTimeMillis" =>
            event_time_millis,
          "subscriptionNotification" => {
            "notificationType" => 4,
            "purchaseToken" =>
              "google-purchase-token"
          }
        }
      )

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        event,
        failing_client
      )
    end
  end

  test "unknown billing product is permanently rejected" do
    event =
      subscription_event(
        notification_type: 4
      )

    purchase =
      valid_purchase(
        state:
          "SUBSCRIPTION_STATE_ACTIVE"
      )

    purchase[
      "lineItems"
    ].first[
      "productId"
    ] =
      "fake_subscription"

    client =
      api_client do |
        _package_name,
        _purchase_token
      |
        purchase
      end

    assert_raises(
      StoreSubscriptionEventVerificationService::
        RejectedNotification
    ) do
      verify(
        event,
        client
      )
    end
  end

  test "temporary API failure is propagated" do
    event =
      subscription_event(
        notification_type: 2
      )

    client =
      api_client do |
        _package_name,
        _purchase_token
      |
        raise StoreSubscriptionEventVerificationService::
                TemporaryFailure,
              "Google API unavailable"
      end

    error =
      assert_raises(
        StoreSubscriptionEventVerificationService::
          TemporaryFailure
      ) do
        verify(
          event,
          client
        )
      end

    assert_includes(
      error.message,
      "Google API unavailable"
    )
  end

  test "missing package configuration is temporary failure" do
    event =
      subscription_event(
        notification_type: 4
      )

    verifier =
      GooglePlayStoreSubscriptionVerifier.new(
        api_client:
          failing_client,
        package_name: nil
      )

    error =
      assert_raises(
        StoreSubscriptionEventVerificationService::
          TemporaryFailure
      ) do
        verifier.call(
          event: event
        )
      end

    assert_includes(
      error.message,
      "package name is not configured"
    )
  end

    test "missing Google purchase is permanently rejected" do
    event =
      subscription_event(
        notification_type: 4
      )

    client =
      api_client do |
        _package_name,
        _purchase_token
      |
        raise GooglePlayDeveloperApiClient::
                NotFound,
              "Google Play subscription was not found"
      end

    error =
      assert_raises(
        StoreSubscriptionEventVerificationService::
          RejectedNotification
      ) do
        verify(
          event,
          client
        )
      end

    assert_includes(
      error.message,
      "subscription was not found"
    )
  end

  test "Google authentication failure is retryable" do
    event =
      subscription_event(
        notification_type: 2
      )

    client =
      api_client do |
        _package_name,
        _purchase_token
      |
        raise GooglePlayDeveloperApiClient::
                AuthenticationError,
              "Google authentication failed"
      end

    error =
      assert_raises(
        StoreSubscriptionEventVerificationService::
          TemporaryFailure
      ) do
        verify(
          event,
          client
        )
      end

    assert_includes(
      error.message,
      "Google authentication failed"
    )
  end

  test "Google API failure is retryable" do
    event =
      subscription_event(
        notification_type: 2
      )

    client =
      api_client do |
        _package_name,
        _purchase_token
      |
        raise GooglePlayDeveloperApiClient::
                RequestFailed,
              "Google Play API returned HTTP 500"
      end

    error =
      assert_raises(
        StoreSubscriptionEventVerificationService::
          TemporaryFailure
      ) do
        verify(
          event,
          client
        )
      end

    assert_includes(
      error.message,
      "HTTP 500"
    )
  end

  private

  def verify(event, client)
    GooglePlayStoreSubscriptionVerifier
      .new(
        api_client: client,
        package_name:
          PACKAGE_NAME
      )
      .call(
        event: event
      )
  end

  def api_client(&block)
    client =
      Object.new

    client.define_singleton_method(
      :fetch_subscription
    ) do |
      package_name:,
      purchase_token:
    |
      block.call(
        package_name,
        purchase_token
      )
    end

    client
  end

  def failing_client
    api_client do |
      _package_name,
      _purchase_token
    |
      raise(
        "Developer API should not be called"
      )
    end
  end

  def subscription_event(
    notification_type:
  )
    create_event(
      decoded_payload: {
        "version" => "1.0",
        "packageName" =>
          PACKAGE_NAME,
        "eventTimeMillis" =>
          event_time_millis,
        "subscriptionNotification" => {
          "version" => "1.0",
          "notificationType" =>
            notification_type,
          "purchaseToken" =>
            "google-purchase-token"
        }
      }
    )
  end

  def create_event(decoded_payload:)
    @event_sequence += 1

    encoded =
      Base64.strict_encode64(
        JSON.generate(
          decoded_payload
        )
      )

    StoreSubscriptionEvent.create!(
      provider: "google_play",
      provider_event_id:
        "google-verifier-event-#{@event_sequence}",
      event_type:
        "notification_received",
      environment: "sandbox",
      metadata: {},
      raw_payload: {
        "message" => {
          "messageId" =>
            "google-verifier-message-#{@event_sequence}",
          "data" =>
            encoded
        }
      }
    )
  end

  def event_time_millis
    (
      @event_time.to_f *
      1000
    ).to_i.to_s
  end

  def valid_purchase(state:)
    {
      "kind" =>
        "androidpublisher#subscriptionPurchaseV2",

      "startTime" =>
        @starts_at.iso8601,

      "subscriptionState" =>
        state,

      "acknowledgementState" =>
        "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",

      "lineItems" => [
        {
          "productId" =>
            "matchmuster_plus",

          "expiryTime" =>
            @ends_at.iso8601,

          "latestSuccessfulOrderId" =>
            "GPA.1234-5678-9012-34567",

          "autoRenewingPlan" => {
            "autoRenewEnabled" =>
              true
          },

          "offerDetails" => {
            "basePlanId" =>
              "monthly"
          }
        }
      ]
    }
  end
end
