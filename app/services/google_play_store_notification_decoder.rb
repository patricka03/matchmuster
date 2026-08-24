require "base64"
require "json"

class GooglePlayStoreNotificationDecoder
  class InvalidNotification <
    StandardError
  end

  class << self
    def call(
      event:,
      package_name:
    )
      new(
        event: event,
        package_name:
          package_name
      ).call
    end
  end

  def initialize(
    event:,
    package_name:
  )
    @event = event

    @package_name =
      package_name.to_s.strip
  end

  def call
    validate_event_provider!

    payload =
      decoded_payload

    validate_package!(
      payload
    )

    common = {
      package_name:
        payload.fetch(
          "packageName"
        ),

      event_time:
        event_time!(
          payload
        )
    }

    if payload[
      "testNotification"
    ].is_a?(Hash)

      return common.merge(
        kind:
          "test_notification",
        notification_type:
          nil,
        purchase_token:
          nil
      )
    end

    subscription =
      payload[
        "subscriptionNotification"
      ]

    if subscription.is_a?(Hash)
      return common.merge(
        subscription_result!(
          subscription
        )
      )
    end

    voided =
      payload[
        "voidedPurchaseNotification"
      ]

    if voided.is_a?(Hash)
      return common.merge(
        voided_result!(
          voided
        )
      )
    end

    common.merge(
      kind:
        "unsupported",
      notification_type:
        nil,
      purchase_token:
        nil
    )
  end

  private

  attr_reader :event,
              :package_name

  def validate_event_provider!
    return if
      event.provider ==
        "google_play"

    raise InvalidNotification,
          "Store event is not from Google Play"
  end

  def decoded_payload
    message =
      event.raw_payload[
        "message"
      ]

    unless message.is_a?(Hash)
      raise InvalidNotification,
            "Google Pub/Sub message is missing"
    end

    encoded_data =
      message[
        "data"
      ].to_s.strip

    if encoded_data.blank?
      raise InvalidNotification,
            "Google Pub/Sub message data is missing"
    end

    decoded =
      Base64.strict_decode64(
        encoded_data
      )

    payload =
      JSON.parse(
        decoded
      )

    unless payload.is_a?(Hash)
      raise InvalidNotification,
            "Google notification data must be an object"
    end

    payload.deep_stringify_keys

  rescue ArgumentError,
         JSON::ParserError

    raise InvalidNotification,
          "Google notification data is invalid"
  end

  def validate_package!(payload)
    if package_name.blank?
      raise InvalidNotification,
            "Google Play package name is not configured"
    end

    received_package =
      payload[
        "packageName"
      ].to_s.strip

    if received_package.blank?
      raise InvalidNotification,
            "Google notification package name is missing"
    end

    return if
      received_package ==
        package_name

    raise InvalidNotification,
          "Google notification package name does not match"
  end

  def event_time!(payload)
    milliseconds =
      Integer(
        payload[
          "eventTimeMillis"
        ].to_s,
        exception: false
      )

    unless milliseconds&.positive?
      raise InvalidNotification,
            "Google notification event time is invalid"
    end

    Time.zone.at(
      milliseconds /
        1000.0
    )
  end

  def subscription_result!(subscription)
    notification_type =
      Integer(
        subscription[
          "notificationType"
        ].to_s,
        exception: false
      )

    unless notification_type&.positive?
      raise InvalidNotification,
            "Google subscription notification type is invalid"
    end

    purchase_token =
      subscription[
        "purchaseToken"
      ].to_s.strip

    if purchase_token.blank?
      raise InvalidNotification,
            "Google subscription purchase token is missing"
    end

    {
      kind:
        "subscription",

      notification_type:
        notification_type,

      purchase_token:
        purchase_token
    }
  end

  def voided_result!(voided)
    purchase_token =
      voided[
        "purchaseToken"
      ].to_s.strip

    if purchase_token.blank?
      raise InvalidNotification,
            "Google voided purchase token is missing"
    end

    product_type =
      Integer(
        voided[
          "productType"
        ].to_s,
        exception: false
      )

    {
      kind:
        "voided_purchase",

      notification_type:
        nil,

      purchase_token:
        purchase_token,

      product_type:
        product_type,

      order_id:
        voided[
          "orderId"
        ].to_s.presence
    }
  end
end
