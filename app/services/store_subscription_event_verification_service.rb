class StoreSubscriptionEventVerificationService
  class VerificationError < StandardError; end
  class TemporaryFailure < VerificationError; end
  class RejectedNotification < VerificationError; end
  class InvalidResult < VerificationError; end

  class << self
    def call(
      event:,
      verifier:
    )
      new(
        event: event,
        verifier: verifier
      ).call
    end
  end

  def initialize(
    event:,
    verifier:
  )
    @event = event
    @verifier = verifier
  end

  def call
    return event if terminal?

    verify_event! unless
      event.verified?

    return event if
      event.verification_rejected?

    process_verified_event!

    event
  end

  private

  attr_reader :event,
              :verifier

  def terminal?
    event.processed? ||
      event.ignored?
  end

  def verify_event!
    result =
      verifier.call(
        event: event
      )

    attributes =
      normalized_result!(
        result
      )

    event.with_lock do
      return if
        event.verified? ||
        event.verification_rejected?

      event.update!(
        attributes.merge(
          verification_status:
            "verified",
          verification_checked_at:
            Time.current,
          verification_error:
            nil
        )
      )
    end

  rescue RejectedNotification => error
    record_rejection!(
      error
    )

  rescue StandardError => error
    record_verification_failure!(
      error
    )

    raise
  end

  def process_verified_event!
    return unless event.verified?

    StoreSubscriptionEventProcessor.call(
      event: event
    )
  end

  def normalized_result!(result)
    unless result.is_a?(Hash)
      raise InvalidResult,
            "Store verifier result must be an object"
    end

    result =
      result.deep_symbolize_keys

    event_type =
      result[
        :event_type
      ].to_s.strip

    if event_type.blank?
      raise InvalidResult,
            "Verified event type is missing"
    end

    environment =
      result[
        :environment
      ].to_s.strip

    unless StoreSubscriptionEvent::
      ENVIRONMENTS.include?(
        environment
      )

      raise InvalidResult,
            "Verified environment is invalid"
    end

    metadata =
      result[
        :metadata
      ]

    unless metadata.is_a?(Hash)
      raise InvalidResult,
            "Verified metadata must be an object"
    end

    {
      event_type: event_type,

      environment: environment,

      provider_subscription_id:
        result[
          :provider_subscription_id
        ].to_s.presence,

      occurred_at:
        normalize_occurred_at!(
          result[
            :occurred_at
          ]
        ),

      metadata:
        metadata.deep_stringify_keys
    }
  end

  def normalize_occurred_at!(value)
    return nil if value.nil?

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

    raise InvalidResult,
          "Verified occurrence time is invalid"
  end

  def record_rejection!(error)
    event.reload

    return if
      event.verified? ||
      event.verification_rejected?

    event.mark_verification_rejected!(
      reason: error
    )
  end

  def record_verification_failure!(error)
    event.reload

    return if
      event.verified? ||
      event.verification_rejected?

    event.mark_verification_failed!(
      error: error
    )
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
