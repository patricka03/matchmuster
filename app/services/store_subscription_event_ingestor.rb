require "digest"

class StoreSubscriptionEventIngestor
  class IngestionError < StandardError; end
  class UnsupportedProvider < IngestionError; end
  class UnsupportedEnvironment < IngestionError; end
  class InvalidPayload < IngestionError; end
  class PayloadConflict < IngestionError; end

  RECEIVED_EVENT_TYPE =
    "notification_received"

  class << self
    def call(
      provider:,
      raw_payload:,
      environment: nil
    )
      new(
        provider: provider,
        raw_payload: raw_payload,
        environment: environment
      ).call
    end
  end

  def initialize(
    provider:,
    raw_payload:,
    environment: nil
  )
    @provider =
      provider.to_s

    @raw_payload =
      normalize_payload(
        raw_payload
      )

    @environment =
      (
        environment.presence ||
        default_environment
      ).to_s
  end

  def call
    validate_provider!
    validate_environment!

    event_id =
      provider_event_id!

    event =
      find_existing_event(
        event_id
      ) ||
      create_event!(
        event_id
      )

    ensure_matching_replay!(
      event
    )

    event
  end

  private

  attr_reader :provider,
              :raw_payload,
              :environment

  def normalize_payload(payload)
    payload =
      payload.to_unsafe_h if
        payload.respond_to?(
          :to_unsafe_h
        )

    unless payload.is_a?(Hash)
      raise InvalidPayload,
            "Store notification payload must be a JSON object"
    end

    payload.deep_stringify_keys
  end

  def default_environment
    Rails.env.production? ?
      "production" :
      "sandbox"
  end

  def validate_provider!
    return if
      StoreSubscriptionEvent::PROVIDERS
        .include?(
          provider
        )

    raise UnsupportedProvider,
          "Unsupported subscription provider: #{provider}"
  end

  def validate_environment!
    return if
      StoreSubscriptionEvent::ENVIRONMENTS
        .include?(
          environment
        )

    raise UnsupportedEnvironment,
          "Unsupported subscription environment: #{environment}"
  end

  def provider_event_id!
    case provider
    when "google_play"
      google_event_id!
    when "apple"
      apple_event_id!
    else
      raise UnsupportedProvider,
            "Unsupported subscription provider: #{provider}"
    end
  end

  def google_event_id!
    message =
      raw_payload[
        "message"
      ]

    unless message.is_a?(Hash)
      raise InvalidPayload,
            "Google Play notification message is missing"
    end

    message_id =
      message[
        "messageId"
      ].to_s.strip

    return message_id if
      message_id.present?

    raise InvalidPayload,
          "Google Play notification message ID is missing"
  end

  def apple_event_id!
    signed_payload =
      raw_payload[
        "signedPayload"
      ].to_s.strip

    if signed_payload.blank?
      raise InvalidPayload,
            "Apple signed notification payload is missing"
    end

    digest =
      Digest::SHA256.hexdigest(
        signed_payload
      )

    "sha256:#{digest}"
  end

  def find_existing_event(event_id)
    StoreSubscriptionEvent.find_by(
      provider: provider,
      provider_event_id: event_id
    )
  end

  def create_event!(event_id)
    StoreSubscriptionEvent.create!(
      provider: provider,
      provider_event_id: event_id,
      event_type:
        RECEIVED_EVENT_TYPE,
      environment: environment,
      processing_status: "pending",
      verification_status: "pending",
      metadata: {},
      raw_payload: raw_payload
    )
  rescue ActiveRecord::RecordNotUnique
    find_existing_event!(
      event_id
    )
  rescue ActiveRecord::RecordInvalid => error
    unless error.record.errors.of_kind?(
      :provider_event_id,
      :taken
    )
      raise
    end

    find_existing_event!(
      event_id
    )
  end

  def find_existing_event!(event_id)
    StoreSubscriptionEvent.find_by!(
      provider: provider,
      provider_event_id: event_id
    )
  end

  def ensure_matching_replay!(event)
    matching =
      event.environment ==
        environment &&
      event.raw_payload ==
        raw_payload

    return if matching

    raise PayloadConflict,
          "Store notification identifier was reused with different data"
  end
end
