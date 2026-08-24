class AppleSignedDataVerifier
  class VerificationError < StandardError; end
  class ConfigurationError < VerificationError; end
  class InvalidPayload < VerificationError; end
  class InvalidAppIdentifier < VerificationError; end
  class InvalidEnvironment < VerificationError; end

  ENVIRONMENTS = {
    "sandbox" => "Sandbox",
    "production" => "Production"
  }.freeze

  def initialize(
    jws_verifier:,
    bundle_id:,
    environment:,
    app_apple_id: nil
  )
    @jws_verifier =
      jws_verifier

    @bundle_id =
      bundle_id.to_s.strip

    @environment =
      environment.to_s.strip.downcase

    @app_apple_id =
      app_apple_id.to_s.strip.presence

    validate_configuration!
  end

  def verify_notification(signed_payload)
    payload =
      verified_payload!(
        signed_payload
      )

    context =
      notification_context!(
        payload
      )

    validate_app_context!(
      context
    )

    payload
  end

  def verify_transaction(signed_payload)
    payload =
      verified_payload!(
        signed_payload
      )

    validate_bundle_id!(
      payload[
        "bundleId"
      ]
    )

    validate_environment!(
      payload[
        "environment"
      ]
    )

    payload
  end

  def verify_renewal_info(signed_payload)
    payload =
      verified_payload!(
        signed_payload
      )

    validate_environment!(
      payload[
        "environment"
      ]
    )

    payload
  end

  private

  attr_reader :jws_verifier,
              :bundle_id,
              :environment,
              :app_apple_id

  def validate_configuration!
    if bundle_id.blank?
      raise ConfigurationError,
            "Apple bundle ID is not configured"
    end

    unless ENVIRONMENTS.key?(
      environment
    )
      raise ConfigurationError,
            "Apple environment is not configured correctly"
    end

    if production? &&
       app_apple_id.blank?

      raise ConfigurationError,
            "Apple app ID is required in production"
    end
  end

  def verified_payload!(signed_payload)
    signed_payload =
      signed_payload.to_s.strip

    if signed_payload.blank?
      raise InvalidPayload,
            "Apple signed data is missing"
    end

    payload =
      jws_verifier.verify(
        signed_payload
      )

    unless payload.is_a?(Hash)
      raise InvalidPayload,
            "Verified Apple signed data must be an object"
    end

    payload.deep_stringify_keys
  end

  def notification_context!(payload)
    context =
      payload[
        "data"
      ]

    context ||=
      payload[
        "summary"
      ]

    context ||=
      payload[
        "appData"
      ]

    unless context.is_a?(Hash)
      raise InvalidPayload,
            "Apple notification application data is missing"
    end

    context.deep_stringify_keys
  end

  def validate_app_context!(context)
    validate_bundle_id!(
      context[
        "bundleId"
      ]
    )

    validate_environment!(
      context[
        "environment"
      ]
    )

    validate_app_apple_id!(
      context[
        "appAppleId"
      ]
    )
  end

  def validate_bundle_id!(value)
    return if
      value.to_s ==
        bundle_id

    raise InvalidAppIdentifier,
          "Apple bundle ID does not match MatchMuster"
  end

  def validate_environment!(value)
    expected =
      ENVIRONMENTS.fetch(
        environment
      )

    return if
      value.to_s ==
        expected

    raise InvalidEnvironment,
          "Apple environment does not match the configured environment"
  end

  def validate_app_apple_id!(value)
    return unless
      production?

    return if
      value.to_s ==
        app_apple_id

    raise InvalidAppIdentifier,
          "Apple app ID does not match MatchMuster"
  end

  def production?
    environment ==
      "production"
  end
end
