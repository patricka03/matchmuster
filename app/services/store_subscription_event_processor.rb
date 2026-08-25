class StoreSubscriptionEventProcessor
  class ProcessingError < StandardError; end
  class UnverifiedEvent < ProcessingError; end
  class InvalidMetadata < ProcessingError; end

  MissingTeam =
    StoreSubscriptionTeamResolver::MissingTeam

  MissingSubscriptionId =
    StoreSubscriptionTeamResolver::MissingSubscriptionId

  SubscriptionOwnershipConflict =
    StoreSubscriptionTeamResolver::OwnershipConflict

  SubscriptionNotLinked =
    StoreSubscriptionTeamResolver::SubscriptionNotLinked

  InvalidAccountToken =
    StoreSubscriptionTeamResolver::InvalidAccountToken

  UnknownAccountToken =
    StoreSubscriptionTeamResolver::UnknownAccountToken

  SUPPORTED_EVENT_TYPES = %w[
    subscription_activated
    subscription_renewed
    subscription_cancelled
    subscription_in_grace_period
    subscription_expired
    subscription_revoked
  ].freeze

  class << self
    def call(event:)
      new(
        event: event
      ).call
    end
  end

  def initialize(event:)
    @event = event
  end

  def call
    return event if terminal?

    process_under_lock

    event
  rescue UnverifiedEvent
    raise
  rescue StandardError => error
    record_processing_failure(
      error
    )

    raise
  end

  private

  attr_reader :event

  def process_under_lock
    event.with_lock do
      next if terminal?

      unless event.verified?
        raise UnverifiedEvent,
              "Store subscription event has not been verified"
      end

      unless supported_event_type?
        event.mark_ignored!(
          reason:
            "Unsupported subscription event type: #{event.event_type}"
        )

        next
      end

      event.mark_processing!

      team =
        StoreSubscriptionTeamResolver.call(
          event: event
        )

      apply_event!(
        team
      )

      event.mark_processed!
    end
  end

  def terminal?
    event.processed? ||
      event.ignored?
  end

  def supported_event_type?
    SUPPORTED_EVENT_TYPES.include?(
      event.event_type
    )
  end

  def apply_event!(team)
    case event.event_type
    when "subscription_activated",
         "subscription_renewed"

      activate_or_renew!(
        team
      )

    when "subscription_cancelled"
      TeamEntitlementService.cancel_paid_plus!(
        team: team,
        access_until:
          timestamp!(
            "ends_at"
          )
      )

    when "subscription_in_grace_period"
      TeamEntitlementService.start_grace_period!(
        team: team,
        ends_at:
          timestamp!(
            "ends_at"
          )
      )

    when "subscription_expired",
         "subscription_revoked"

      TeamEntitlementService.expire!(
        team: team
      )
    end
  end

  def activate_or_renew!(team)
    TeamEntitlementService.activate_paid_plus!(
      team: team,
      provider:
        event.provider,
      provider_subscription_id:
        required_subscription_id!,
      billing_period:
        metadata_value!(
          "billing_period"
        ),
      provider_product_id:
        metadata_value!(
          "product_id"
        ),
      provider_base_plan_id:
        optional_metadata_value(
          "base_plan_id"
        ),
      starts_at:
        timestamp!(
          "starts_at"
        ),
      ends_at:
        timestamp!(
          "ends_at"
        ),
      auto_renews:
        boolean_metadata_value!(
          "auto_renews"
        )
    )
  end

  def required_subscription_id!
    subscription_id =
      event
        .provider_subscription_id
        .to_s
        .strip

    return subscription_id if
      subscription_id.present?

    raise MissingSubscriptionId,
          "Store subscription identifier is missing"
  end

  def metadata_value!(key)
    value =
      event.metadata[
        key
      ]

    return value unless
      value.nil? ||
      value == ""

    raise InvalidMetadata,
          "Missing verified metadata: #{key}"
  end

  def optional_metadata_value(key)
    value =
      event.metadata[
        key
      ]

    value.to_s.presence
  end

  def boolean_metadata_value!(key)
    value =
      metadata_value!(
        key
      )

    return value if
      value == true ||
      value == false

    raise InvalidMetadata,
          "Verified metadata #{key} must be true or false"
  end

  def timestamp!(key)
    value =
      metadata_value!(
        key
      )

    return value.in_time_zone if
      value.respond_to?(
        :in_time_zone
      ) &&
      !value.is_a?(
        String
      )

    Time.zone.iso8601(
      value.to_s
    )

  rescue ArgumentError,
         TypeError

    raise InvalidMetadata,
          "Verified metadata #{key} must be a valid ISO 8601 timestamp"
  end

  def record_processing_failure(error)
    event.reload

    return if terminal?

    event.mark_failed!(
      error: error
    )

  rescue ActiveRecord::RecordNotFound
    nil
  end
end
