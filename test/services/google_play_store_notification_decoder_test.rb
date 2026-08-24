require "test_helper"
require "base64"
require "json"

class GooglePlayStoreNotificationDecoderTest <
  ActiveSupport::TestCase

  PACKAGE_NAME =
    "uk.matchmuster.app"

  EVENT_TIME_MILLIS =
    1_788_264_000_000

  setup do
    @event_sequence = 0
  end

  test "decodes subscription notification" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            EVENT_TIME_MILLIS.to_s,
          "subscriptionNotification" => {
            "version" => "1.0",
            "notificationType" => 4,
            "purchaseToken" =>
              "google-purchase-token"
          }
        }
      )

    result =
      decode(
        event
      )

    assert_equal(
      "subscription",
      result.fetch(
        :kind
      )
    )

    assert_equal(
      4,
      result.fetch(
        :notification_type
      )
    )

    assert_equal(
      "google-purchase-token",
      result.fetch(
        :purchase_token
      )
    )

    assert_equal(
      PACKAGE_NAME,
      result.fetch(
        :package_name
      )
    )

    assert_equal(
      Time.zone.at(
        EVENT_TIME_MILLIS /
          1000.0
      ),
      result.fetch(
        :event_time
      )
    )
  end

  test "decodes test notification" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            EVENT_TIME_MILLIS.to_s,
          "testNotification" => {
            "version" => "1.0"
          }
        }
      )

    result =
      decode(
        event
      )

    assert_equal(
      "test_notification",
      result.fetch(
        :kind
      )
    )

    assert_nil(
      result[
        :purchase_token
      ]
    )
  end

  test "decodes voided subscription purchase" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            EVENT_TIME_MILLIS.to_s,
          "voidedPurchaseNotification" => {
            "purchaseToken" =>
              "voided-token",
            "orderId" =>
              "GPA.1234-5678",
            "productType" => 1,
            "refundType" => 1
          }
        }
      )

    result =
      decode(
        event
      )

    assert_equal(
      "voided_purchase",
      result.fetch(
        :kind
      )
    )

    assert_equal(
      "voided-token",
      result.fetch(
        :purchase_token
      )
    )

    assert_equal(
      1,
      result.fetch(
        :product_type
      )
    )

    assert_equal(
      "GPA.1234-5678",
      result.fetch(
        :order_id
      )
    )
  end

  test "unrelated notification type is safely identified" do
    event =
      create_event(
        decoded_payload: {
          "version" => "1.0",
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            EVENT_TIME_MILLIS.to_s,
          "oneTimeProductNotification" => {
            "notificationType" => 1,
            "purchaseToken" =>
              "one-time-token",
            "sku" => "football-pack"
          }
        }
      )

    result =
      decode(
        event
      )

    assert_equal(
      "unsupported",
      result.fetch(
        :kind
      )
    )
  end

  test "event must belong to Google Play" do
    event =
      create_event(
        provider: "apple",
        decoded_payload: {
          "packageName" =>
            PACKAGE_NAME
        }
      )

    assert_raises(
      GooglePlayStoreNotificationDecoder::
        InvalidNotification
    ) do
      decode(
        event
      )
    end
  end

  test "invalid encoded data is rejected" do
    event =
      create_event(
        encoded_data:
          "not-valid-base64"
      )

    error =
      assert_raises(
        GooglePlayStoreNotificationDecoder::
          InvalidNotification
      ) do
        decode(
          event
        )
      end

    assert_includes(
      error.message,
      "data is invalid"
    )
  end

  test "incorrect package name is rejected" do
    event =
      create_event(
        decoded_payload: {
          "packageName" =>
            "com.fake.application",
          "eventTimeMillis" =>
            EVENT_TIME_MILLIS.to_s,
          "testNotification" => {}
        }
      )

    error =
      assert_raises(
        GooglePlayStoreNotificationDecoder::
          InvalidNotification
      ) do
        decode(
          event
        )
      end

    assert_includes(
      error.message,
      "does not match"
    )
  end

  test "subscription purchase token is required" do
    event =
      create_event(
        decoded_payload: {
          "packageName" =>
            PACKAGE_NAME,
          "eventTimeMillis" =>
            EVENT_TIME_MILLIS.to_s,
          "subscriptionNotification" => {
            "notificationType" => 4
          }
        }
      )

    error =
      assert_raises(
        GooglePlayStoreNotificationDecoder::
          InvalidNotification
      ) do
        decode(
          event
        )
      end

    assert_includes(
      error.message,
      "purchase token is missing"
    )
  end

  private

  def decode(event)
    GooglePlayStoreNotificationDecoder.call(
      event: event,
      package_name:
        PACKAGE_NAME
    )
  end

  def create_event(
    provider: "google_play",
    decoded_payload: nil,
    encoded_data: nil
  )
    @event_sequence += 1

    encoded_data ||=
      Base64.strict_encode64(
        JSON.generate(
          decoded_payload
        )
      )

    StoreSubscriptionEvent.create!(
      provider: provider,
      provider_event_id:
        "google-decoder-event-#{@event_sequence}",
      event_type:
        "notification_received",
      environment: "sandbox",
      metadata: {},
      raw_payload: {
        "message" => {
          "messageId" =>
            "google-decoder-message-#{@event_sequence}",
          "data" =>
            encoded_data
        }
      }
    )
  end
end
