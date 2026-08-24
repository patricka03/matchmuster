class GooglePlaySubscriptionStateMapper
  class InvalidPurchase <
    StandardError
  end

  class UnknownProduct <
    InvalidPurchase
  end

  ACTIVE_STATE =
    "SUBSCRIPTION_STATE_ACTIVE"

  GRACE_PERIOD_STATE =
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"

  CANCELLED_STATE =
    "SUBSCRIPTION_STATE_CANCELED"

  EXPIRED_STATES = %w[
    SUBSCRIPTION_STATE_EXPIRED
    SUBSCRIPTION_STATE_ON_HOLD
    SUBSCRIPTION_STATE_PAUSED
    SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED
  ].freeze

  IGNORED_STATES = %w[
    SUBSCRIPTION_STATE_PENDING
    SUBSCRIPTION_STATE_UNSPECIFIED
  ].freeze

  class << self
    def call(
      decoded_notification:,
      purchase:
    )
      new(
        decoded_notification:
          decoded_notification,
        purchase: purchase
      ).call
    end
  end

  def initialize(
    decoded_notification:,
    purchase:
  )
    unless decoded_notification.is_a?(Hash)
      raise InvalidPurchase,
            "Decoded Google notification must be an object"
    end

    unless purchase.is_a?(Hash)
      raise InvalidPurchase,
            "Google subscription purchase must be an object"
    end

    @notification =
      decoded_notification.deep_symbolize_keys

    @purchase =
      purchase.deep_stringify_keys
  end

  def call
    validate_notification_kind!

    state =
      subscription_state!

    if IGNORED_STATES.include?(
      state
    )
      return base_result.merge(
        event_type:
          "google_subscription_pending",
        metadata: {
          "google_subscription_state" =>
            state
        }
      )
    end

    line_item =
      known_line_item!

    event_type =
      event_type_for!(
        state
      )

    base_result.merge(
      event_type:
        event_type,

      metadata:
        metadata_for(
          event_type: event_type,
          state: state,
          line_item: line_item
        )
    )
  end

  private

  attr_reader :notification,
              :purchase

  def validate_notification_kind!
    kind =
      notification[
        :kind
      ].to_s

    return if
      kind == "subscription"

    if kind ==
       "voided_purchase" &&
       notification[
         :product_type
       ] == 1

      return
    end

    raise InvalidPurchase,
          "Google notification is not for a subscription"
  end

  def subscription_state!
    state =
      purchase[
        "subscriptionState"
      ].to_s.strip

    if state.blank?
      raise InvalidPurchase,
            "Google subscription state is missing"
    end

    state
  end

  def base_result
    {
      environment:
        sandbox_purchase? ?
          "sandbox" :
          "production",

      provider_subscription_id:
        purchase_token!,

      occurred_at:
        notification[
          :event_time
        ]
    }
  end

  def sandbox_purchase?
    purchase[
      "testPurchase"
    ].is_a?(
      Hash
    )
  end

  def purchase_token!
    token =
      notification[
        :purchase_token
      ].to_s.strip

    if token.blank?
      raise InvalidPurchase,
            "Google purchase token is missing"
    end

    token
  end

  def event_type_for!(state)
    return "subscription_revoked" if
      revoked_notification?

    case state
    when ACTIVE_STATE
      renewed_notification? ?
        "subscription_renewed" :
        "subscription_activated"

    when GRACE_PERIOD_STATE
      "subscription_in_grace_period"

    when CANCELLED_STATE
      "subscription_cancelled"

    when *EXPIRED_STATES
      "subscription_expired"

    else
      raise InvalidPurchase,
            "Unsupported Google subscription state: #{state}"
    end
  end

  def renewed_notification?
    notification[
      :notification_type
    ] == 2
  end

  def revoked_notification?
    notification[
      :kind
    ].to_s ==
      "voided_purchase" ||
      notification[
        :notification_type
      ] == 12
  end

  def known_line_item!
    line_items =
      purchase[
        "lineItems"
      ]

    unless line_items.is_a?(Array)
      raise InvalidPurchase,
            "Google subscription line items are missing"
    end

    line_item =
      line_items.find do |item|
        item.is_a?(Hash) &&
          known_product?(
            item
          )
      end

    return line_item if
      line_item

    raise UnknownProduct,
          "Google subscription does not contain a MatchMuster product"
  end

  def known_product?(line_item)
    product_id =
      line_item[
        "productId"
      ].to_s

    base_plan_id =
      line_item.dig(
        "offerDetails",
        "basePlanId"
      ).to_s

    BillingProductCatalog::
      BILLING_PERIODS.any? do |
        billing_period
      |
        BillingProductCatalog.valid_identity?(
          provider:
            "google_play",
          billing_period:
            billing_period,
          product_id:
            product_id,
          base_plan_id:
            base_plan_id
        )
      end
  end

  def billing_period_for!(
    product_id:,
    base_plan_id:
  )
    billing_period =
      BillingProductCatalog::
        BILLING_PERIODS.find do |
          period
        |
          BillingProductCatalog.valid_identity?(
            provider:
              "google_play",
            billing_period:
              period,
            product_id:
              product_id,
            base_plan_id:
              base_plan_id
          )
        end

    return billing_period if
      billing_period

    raise UnknownProduct,
          "Unknown MatchMuster Google Play product"
  end

  def metadata_for(
    event_type:,
    state:,
    line_item:
  )
    metadata = {
      "google_subscription_state" =>
        state
    }

    case event_type
    when "subscription_activated",
         "subscription_renewed"

      metadata.merge(
        active_metadata(
          line_item
        )
      )

    when "subscription_cancelled",
         "subscription_in_grace_period"

      metadata.merge(
        "ends_at" =>
          expiry_time!(
            line_item
          ).iso8601
      )

    else
      metadata
    end
  end

  def active_metadata(line_item)
    product_id =
      line_item[
        "productId"
      ].to_s

    base_plan_id =
      line_item.dig(
        "offerDetails",
        "basePlanId"
      ).to_s

    {
      "billing_period" =>
        billing_period_for!(
          product_id:
            product_id,
          base_plan_id:
            base_plan_id
        ),

      "product_id" =>
        product_id,

      "base_plan_id" =>
        base_plan_id,

      "starts_at" =>
        start_time!.iso8601,

      "ends_at" =>
        expiry_time!(
          line_item
        ).iso8601,

      "auto_renews" =>
        auto_renews?(
          line_item
        )
    }
  end

  def start_time!
    parse_time!(
      purchase[
        "startTime"
      ],
      field:
        "start time"
    )
  end

  def expiry_time!(line_item)
    parse_time!(
      line_item[
        "expiryTime"
      ],
      field:
        "expiry time"
    )
  end

  def parse_time!(value, field:)
    Time.zone.iso8601(
      value.to_s
    )

  rescue ArgumentError,
         TypeError

    raise InvalidPurchase,
          "Google subscription #{field} is invalid"
  end

  def auto_renews?(line_item)
    value =
      line_item.dig(
        "autoRenewingPlan",
        "autoRenewEnabled"
      )

    return value if
      value == true ||
      value == false

    raise InvalidPurchase,
          "Google subscription auto-renewal state is invalid"
  end
end
