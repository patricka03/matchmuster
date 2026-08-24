require "test_helper"

class GooglePlaySubscriptionStateMapperTest <
  ActiveSupport::TestCase

  setup do
    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_time =
      @starts_at + 1.hour
  end

  test "active purchase becomes activation" do
    result =
      map(
        notification_type: 4,
        state:
          "SUBSCRIPTION_STATE_ACTIVE"
      )

    assert_equal(
      "subscription_activated",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      "production",
      result.fetch(
        :environment
      )
    )

    assert_equal(
      "google-purchase-token",
      result.fetch(
        :provider_subscription_id
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
      "matchmuster_plus",
      metadata.fetch(
        "product_id"
      )
    )

    assert_equal(
      "monthly",
      metadata.fetch(
        "base_plan_id"
      )
    )

    assert_equal(
      true,
      metadata.fetch(
        "auto_renews"
      )
    )
  end

  test "renewed purchase becomes renewal" do
    result =
      map(
        notification_type: 2,
        state:
          "SUBSCRIPTION_STATE_ACTIVE"
      )

    assert_equal(
      "subscription_renewed",
      result.fetch(
        :event_type
      )
    )
  end

  test "grace period retains access until expiry" do
    result =
      map(
        notification_type: 6,
        state:
          "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"
      )

    assert_equal(
      "subscription_in_grace_period",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      @ends_at.iso8601,
      result
        .fetch(
          :metadata
        )
        .fetch(
          "ends_at"
        )
    )
  end

  test "cancelled purchase preserves access until expiry" do
    purchase =
      valid_purchase(
        state:
          "SUBSCRIPTION_STATE_CANCELED",
        auto_renews: false
      )

    result =
      map(
        notification_type: 3,
        purchase: purchase
      )

    assert_equal(
      "subscription_cancelled",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      @ends_at.iso8601,
      result
        .fetch(
          :metadata
        )
        .fetch(
          "ends_at"
        )
    )
  end

  test "account hold removes entitlement" do
    result =
      map(
        notification_type: 5,
        state:
          "SUBSCRIPTION_STATE_ON_HOLD"
      )

    assert_equal(
      "subscription_expired",
      result.fetch(
        :event_type
      )
    )
  end

  test "revoked notification removes entitlement immediately" do
    result =
      map(
        notification_type: 12,
        state:
          "SUBSCRIPTION_STATE_EXPIRED"
      )

    assert_equal(
      "subscription_revoked",
      result.fetch(
        :event_type
      )
    )
  end

  test "pending purchase is safely ignored by processor" do
    result =
      map(
        notification_type: 4,
        state:
          "SUBSCRIPTION_STATE_PENDING"
      )

    assert_equal(
      "google_subscription_pending",
      result.fetch(
        :event_type
      )
    )
  end

  test "test purchase uses sandbox environment" do
    purchase =
      valid_purchase(
        state:
          "SUBSCRIPTION_STATE_ACTIVE"
      ).merge(
        "testPurchase" => {}
      )

    result =
      map(
        notification_type: 4,
        purchase: purchase
      )

    assert_equal(
      "sandbox",
      result.fetch(
        :environment
      )
    )
  end

  test "unknown product is rejected" do
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
      "another_product"

    assert_raises(
      GooglePlaySubscriptionStateMapper::
        UnknownProduct
    ) do
      map(
        notification_type: 4,
        purchase: purchase
      )
    end
  end

  private

  def map(
    notification_type:,
    state: nil,
    purchase: nil
  )
    purchase ||=
      valid_purchase(
        state: state
      )

    GooglePlaySubscriptionStateMapper.call(
      decoded_notification: {
        kind: "subscription",
        notification_type:
          notification_type,
        purchase_token:
          "google-purchase-token",
        package_name:
          "uk.matchmuster.app",
        event_time:
          @event_time
      },
      purchase: purchase
    )
  end

  def valid_purchase(
    state:,
    auto_renews: true
  )
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
              auto_renews
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
