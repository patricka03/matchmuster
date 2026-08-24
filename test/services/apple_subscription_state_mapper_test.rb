require "test_helper"

class AppleSubscriptionStateMapperTest <
    ActiveSupport::TestCase
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

  test "maps monthly subscription activation" do
    result =
      map(
        notification_type:
          "SUBSCRIBED",
        subtype:
          "INITIAL_BUY"
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

    assert_nil(
      metadata[
        "base_plan_id"
      ]
    )

    assert_equal(
      @starts_at.iso8601,
      metadata.fetch(
        "starts_at"
      )
    )

    assert_equal(
      @ends_at.iso8601,
      metadata.fetch(
        "ends_at"
      )
    )

    assert_equal(
      true,
      metadata.fetch(
        "auto_renews"
      )
    )
  end

  test "maps annual subscription renewal" do
    transaction =
      valid_transaction(
        product_id:
          "matchmuster_plus_annual",
        ends_at:
          @starts_at + 1.year
      )

    result =
      map(
        notification_type:
          "DID_RENEW",
        transaction:
          transaction
      )

    assert_equal(
      "subscription_renewed",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      "annual",
      result
        .fetch(
          :metadata
        )
        .fetch(
          "billing_period"
        )
    )
  end

  test "maps disabled auto renewal as cancellation" do
    result =
      map(
        notification_type:
          "DID_CHANGE_RENEWAL_STATUS",
        subtype:
          "AUTO_RENEW_DISABLED"
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

  test "maps billing grace period" do
    grace_ends_at =
      @ends_at + 3.days

    result =
      map(
        notification_type:
          "DID_FAIL_TO_RENEW",
        subtype:
          "GRACE_PERIOD",
        renewal_info: {
          "autoRenewStatus" => 1,
          "gracePeriodExpiresDate" =>
            milliseconds(
              grace_ends_at
            )
        }
      )

    assert_equal(
      "subscription_in_grace_period",
      result.fetch(
        :event_type
      )
    )

    assert_equal(
      grace_ends_at.iso8601,
      result
        .fetch(
          :metadata
        )
        .fetch(
          "ends_at"
        )
    )
  end

  test "maps expired and revoked notifications" do
    {
      "EXPIRED" =>
        "subscription_expired",
      "GRACE_PERIOD_EXPIRED" =>
        "subscription_expired",
      "REFUND" =>
        "subscription_revoked",
      "REVOKE" =>
        "subscription_revoked"
    }.each do |
      notification_type,
      expected_event_type
    |
      result =
        map(
          notification_type:
            notification_type
        )

      assert_equal(
        expected_event_type,
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
    end
  end

  test "safely ignores non lifecycle notifications" do
    {
      "TEST" =>
        "apple_test",
      "PRICE_INCREASE" =>
        "apple_price_increase"
    }.each do |
      notification_type,
      expected_event_type
    |
      result =
        map(
          notification_type:
            notification_type,
          transaction: nil,
          renewal_info: nil
        )

      assert_equal(
        expected_event_type,
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
  end

  test "rejects unknown Apple product" do
    transaction =
      valid_transaction(
        product_id:
          "another_application_product"
      )

    assert_raises(
      AppleSubscriptionStateMapper::
        UnknownProduct
    ) do
      map(
        notification_type:
          "SUBSCRIBED",
        transaction:
          transaction
      )
    end
  end

  test "rejects invalid auto renewal state" do
    assert_raises(
      AppleSubscriptionStateMapper::
        InvalidPurchase
    ) do
      map(
        notification_type:
          "SUBSCRIBED",
        renewal_info: {
          "autoRenewStatus" =>
            "unknown"
        }
      )
    end
  end

  test "rejects non subscription transaction" do
    transaction =
      valid_transaction

    transaction[
      "type"
    ] =
      "Consumable"

    assert_raises(
      AppleSubscriptionStateMapper::
        InvalidPurchase
    ) do
      map(
        notification_type:
          "SUBSCRIBED",
        transaction:
          transaction
      )
    end
  end

  private

  def map(
    notification_type:,
    subtype: nil,
    transaction:
      valid_transaction,
    renewal_info:
      valid_renewal_info
  )
    AppleSubscriptionStateMapper.call(
      decoded_notification: {
        notification_type:
          notification_type,
        subtype:
          subtype,
        notification_uuid:
          "apple-notification-uuid",
        signed_at:
          @signed_at,
        environment:
          "sandbox",
        transaction:
          transaction,
        renewal_info:
          renewal_info
      }
    )
  end

  def valid_transaction(
    product_id:
      "matchmuster_plus_monthly",
    ends_at:
      @ends_at
  )
    {
      "originalTransactionId" =>
        "apple-original-transaction",

      "productId" =>
        product_id,

      "type" =>
        "Auto-Renewable Subscription",

      "purchaseDate" =>
        milliseconds(
          @starts_at
        ),

      "expiresDate" =>
        milliseconds(
          ends_at
        )
    }
  end

  def valid_renewal_info
    {
      "autoRenewStatus" => 1
    }
  end

  def milliseconds(time)
    (
      time.to_f *
      1000
    ).to_i.to_s
  end
end
