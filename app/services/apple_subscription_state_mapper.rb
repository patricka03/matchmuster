class AppleSubscriptionStateMapper
  class InvalidPurchase < StandardError; end
  class UnknownProduct < InvalidPurchase; end

  SUBSCRIPTION_TYPE =
    "Auto-Renewable Subscription"

  class << self
    def call(decoded_notification:)
      new(
        decoded_notification:
          decoded_notification
      ).call
    end
  end

  def initialize(decoded_notification:)
    unless decoded_notification.is_a?(Hash)
      raise InvalidPurchase,
            "Decoded Apple notification must be an object"
    end

    @notification =
      decoded_notification.deep_symbolize_keys
  end

  def call
    notification_type =
      notification_type!

    event_type =
      event_type_for(
        notification_type
      )

    return ignored_result(
      event_type:
        event_type,
      notification_type:
        notification_type
    ) if ignored_event?(
      event_type
    )

    transaction =
      transaction!

    validate_subscription!(
      transaction
    )

    billing_period =
      billing_period_for!(
        transaction
      )

    subscription_id =
      subscription_id!(
        transaction
      )

    {
      event_type:
        event_type,

      environment:
        environment!,

      provider_subscription_id:
        subscription_id,

      occurred_at:
        occurred_at!,

      metadata:
        metadata_for(
          event_type: event_type,
          notification_type:
            notification_type,
          transaction:
            transaction,
          billing_period:
            billing_period
        )
    }
  end

  private

  attr_reader :notification

  def notification_type!
    value =
      notification[
        :notification_type
      ].to_s.strip

    return value if
      value.present?

    raise InvalidPurchase,
          "Apple notification type is missing"
  end

  def subtype
    notification[
      :subtype
    ].to_s.strip.presence
  end

  def event_type_for(notification_type)
    case notification_type
    when "SUBSCRIBED"
      "subscription_activated"

    when "DID_RENEW"
      "subscription_renewed"

    when "DID_CHANGE_RENEWAL_STATUS"
      if subtype ==
         "AUTO_RENEW_DISABLED"

        "subscription_cancelled"

      elsif subtype ==
            "AUTO_RENEW_ENABLED"

        "subscription_renewed"

      else
        ignored_event_type(
          notification_type
        )
      end

    when "DID_FAIL_TO_RENEW"
      subtype ==
        "GRACE_PERIOD" ?
          "subscription_in_grace_period" :
          "subscription_expired"

    when "GRACE_PERIOD_EXPIRED",
         "EXPIRED"

      "subscription_expired"

    when "REFUND",
         "REVOKE"

      "subscription_revoked"

    else
      ignored_event_type(
        notification_type
      )
    end
  end

  def ignored_event_type(notification_type)
    "apple_#{notification_type.downcase}"
  end

  def ignored_event?(event_type)
    event_type.start_with?(
      "apple_"
    )
  end

  def ignored_result(
    event_type:,
    notification_type:
  )
    {
      event_type:
        event_type,

      environment:
        environment!,

      provider_subscription_id:
        nil,

      occurred_at:
        occurred_at!,

      metadata: {
        "apple_notification_type" =>
          notification_type,

        "apple_subtype" =>
          subtype
      }
    }
  end

  def transaction!
    transaction =
      notification[
        :transaction
      ]

    unless transaction.is_a?(Hash)
      raise InvalidPurchase,
            "Verified Apple transaction is missing"
    end

    transaction.deep_stringify_keys
  end

  def renewal_info
    value =
      notification[
        :renewal_info
      ]

    return {} if value.nil?

    unless value.is_a?(Hash)
      raise InvalidPurchase,
            "Verified Apple renewal information is invalid"
    end

    value.deep_stringify_keys
  end

  def validate_subscription!(transaction)
    return if
      transaction[
        "type"
      ] ==
        SUBSCRIPTION_TYPE

    raise InvalidPurchase,
          "Apple transaction is not an auto-renewable subscription"
  end

  def subscription_id!(transaction)
    value =
      transaction[
        "originalTransactionId"
      ].to_s.strip

    return value if
      value.present?

    raise InvalidPurchase,
          "Apple original transaction ID is missing"
  end

  def product_id!(transaction)
    value =
      transaction[
        "productId"
      ].to_s.strip

    return value if
      value.present?

    raise InvalidPurchase,
          "Apple subscription product ID is missing"
  end

  def billing_period_for!(transaction)
    product_id =
      product_id!(
        transaction
      )

    billing_period =
      BillingProductCatalog::
        BILLING_PERIODS.find do |period|
          BillingProductCatalog.valid_identity?(
            provider: "apple",
            billing_period:
              period,
            product_id:
              product_id,
            base_plan_id:
              nil
          )
        end

    return billing_period if
      billing_period

    raise UnknownProduct,
          "Unknown MatchMuster Apple subscription product"
  end

  def environment!
    environment =
      notification[
        :environment
      ].to_s.strip

    return environment if
      StoreSubscriptionEvent::
        ENVIRONMENTS.include?(
          environment
        )

    raise InvalidPurchase,
          "Apple subscription environment is invalid"
  end

  def occurred_at!
    value =
      notification[
        :signed_at
      ]

    if value.respond_to?(
      :in_time_zone
    ) &&
       !value.is_a?(
         String
       )

      return value.in_time_zone
    end

    Time.zone.iso8601(
      value.to_s
    )

  rescue ArgumentError,
         TypeError

    raise InvalidPurchase,
          "Apple notification signed time is invalid"
  end

  def metadata_for(
    event_type:,
    notification_type:,
    transaction:,
    billing_period:
  )
    metadata = {
      "apple_notification_type" =>
        notification_type,

      "apple_subtype" =>
        subtype,

      "product_id" =>
        product_id!(
          transaction
        )
    }

    case event_type
    when "subscription_activated",
         "subscription_renewed"

      metadata.merge(
        active_metadata(
          transaction,
          billing_period
        )
      )

    when "subscription_cancelled"
      metadata.merge(
        "ends_at" =>
          expiry_time!(
            transaction
          ).iso8601
      )

    when "subscription_in_grace_period"
      metadata.merge(
        "ends_at" =>
          grace_period_ends_at!
            .iso8601
      )

    else
      metadata
    end
  end

  def active_metadata(
    transaction,
    billing_period
  )
    {
      "billing_period" =>
        billing_period,

      "base_plan_id" =>
        nil,

      "starts_at" =>
        purchase_time!(
          transaction
        ).iso8601,

      "ends_at" =>
        expiry_time!(
          transaction
        ).iso8601,

      "auto_renews" =>
        auto_renews!
    }
  end

  def purchase_time!(transaction)
    time_from_milliseconds!(
      transaction[
        "purchaseDate"
      ],
      field:
        "purchase date"
    )
  end

  def expiry_time!(transaction)
    time_from_milliseconds!(
      transaction[
        "expiresDate"
      ],
      field:
        "expiry date"
    )
  end

  def grace_period_ends_at!
    time_from_milliseconds!(
      renewal_info[
        "gracePeriodExpiresDate"
      ],
      field:
        "grace-period expiry date"
    )
  end

  def time_from_milliseconds!(
    value,
    field:
  )
    milliseconds =
      value.to_s.strip

    unless milliseconds.match?(
      /\A\d+\z/
    )
      raise InvalidPurchase,
            "Apple subscription #{field} is invalid"
    end

    Time.zone.at(
      milliseconds.to_i /
        1000.0
    )
  end

  def auto_renews!
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

    raise InvalidPurchase,
          "Apple subscription auto-renewal state is invalid"
  end
end
