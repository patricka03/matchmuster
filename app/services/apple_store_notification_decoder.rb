class AppleStoreNotificationDecoder
  class InvalidNotification < StandardError; end

  ENVIRONMENT_MAPPING = {
    "Sandbox" => "sandbox",
    "Production" => "production",
    "sandbox" => "sandbox",
    "production" => "production"
  }.freeze

  class << self
    def call(
      event:,
      signed_data_verifier:
    )
      new(
        event: event,
        signed_data_verifier:
          signed_data_verifier
      ).call
    end
  end

  def initialize(
    event:,
    signed_data_verifier:
  )
    @event = event
    @signed_data_verifier =
      signed_data_verifier
  end

  def call
    validate_provider!

    notification =
      verified_hash!(
        signed_data_verifier
          .verify_notification(
            signed_payload!
          ),
        "notification"
      )

    data =
      optional_hash!(
        notification[
          "data"
        ],
        "notification data"
      )

    {
      notification_type:
        required_string!(
          notification,
          "notificationType",
          "Apple notification type"
        ),

      subtype:
        optional_string(
          notification[
            "subtype"
          ]
        ),

      notification_uuid:
        required_string!(
          notification,
          "notificationUUID",
          "Apple notification UUID"
        ),

      signed_at:
        time_from_milliseconds!(
          notification[
            "signedDate"
          ],
          "Apple notification signed date"
        ),

      environment:
        normalize_environment!(
          data[
            "environment"
          ]
        ),

      transaction:
        verify_nested_payload(
          data[
            "signedTransactionInfo"
          ],
          verifier_method:
            :verify_transaction,
          description:
            "transaction"
        ),

      renewal_info:
        verify_nested_payload(
          data[
            "signedRenewalInfo"
          ],
          verifier_method:
            :verify_renewal_info,
          description:
            "renewal information"
        )
    }
  end

  private

  attr_reader :event,
              :signed_data_verifier

  def validate_provider!
    return if
      event.provider ==
        "apple"

    raise InvalidNotification,
          "Store event is not an Apple notification"
  end

  def signed_payload!
    payload =
      event.raw_payload

    unless payload.is_a?(Hash)
      raise InvalidNotification,
            "Apple notification payload must be an object"
    end

    signed_payload =
      payload
        .deep_stringify_keys[
          "signedPayload"
        ]
        .to_s
        .strip

    if signed_payload.blank?
      raise InvalidNotification,
            "Apple signed notification payload is missing"
    end

    signed_payload
  end

  def verified_hash!(
    value,
    description
  )
    unless value.is_a?(Hash)
      raise InvalidNotification,
            "Verified Apple #{description} must be an object"
    end

    value.deep_stringify_keys
  end

  def optional_hash!(
    value,
    description
  )
    return {} if value.nil?

    verified_hash!(
      value,
      description
    )
  end

  def required_string!(
    object,
    key,
    description
  )
    value =
      object[
        key
      ].to_s.strip

    return value if
      value.present?

    raise InvalidNotification,
          "#{description} is missing"
  end

  def optional_string(value)
    value
      .to_s
      .strip
      .presence
  end

  def time_from_milliseconds!(
    value,
    description
  )
    milliseconds =
      value.to_s.strip

    unless milliseconds.match?(
      /\A\d+\z/
    )
      raise InvalidNotification,
            "#{description} is invalid"
    end

    Time.zone.at(
      milliseconds.to_i /
        1000.0
    )
  end

  def normalize_environment!(value)
    environment =
      ENVIRONMENT_MAPPING[
        value.to_s.strip
      ]

    environment ||=
      event.environment if
        value.to_s.strip.blank?

    return environment if
      StoreSubscriptionEvent::
        ENVIRONMENTS.include?(
          environment
        )

    raise InvalidNotification,
          "Apple notification environment is invalid"
  end

  def verify_nested_payload(
    signed_payload,
    verifier_method:,
    description:
  )
    signed_payload =
      signed_payload.to_s.strip

    return nil if
      signed_payload.blank?

    verified_hash!(
      signed_data_verifier.public_send(
        verifier_method,
        signed_payload
      ),
      description
    )
  end
end
