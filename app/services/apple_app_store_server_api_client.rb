require "faraday"
require "json"
require "jwt"
require "openssl"
require "uri"

class AppleAppStoreServerApiClient
  PRODUCTION_ORIGIN = "https://api.storekit.itunes.apple.com"
  SANDBOX_ORIGIN = "https://api.storekit-sandbox.itunes.apple.com"
  AUDIENCE = "appstoreconnect-v1"
  TOKEN_LIFETIME = 5.minutes

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AuthenticationError < Error; end
  class NotFound < Error; end
  class RequestFailed < Error; end
  class RateLimited < RequestFailed; end
  class ServerError < RequestFailed; end

  def initialize(
    connection: nil,
    issuer_id: ENV["APPLE_ISSUER_ID"],
    key_id: ENV["APPLE_KEY_ID"],
    private_key: ENV["APPLE_PRIVATE_KEY"],
    bundle_id: ENV["APPLE_BUNDLE_ID"],
    environment: ENV["APPLE_STORE_ENVIRONMENT"],
    http_environment: ENV,
    clock: -> { Time.current }
  )
    @connection = connection
    @issuer_id = issuer_id.to_s.strip
    @key_id = key_id.to_s.strip
    @private_key_pem = private_key.to_s
    @bundle_id = bundle_id.to_s.strip
    @environment = environment.to_s.strip.downcase
    @http_environment = http_environment
    @clock = clock
  end

  def fetch_subscription_status(original_transaction_id:)
    validate_configuration!

    transaction_id = required_transaction_id!(original_transaction_id)

    response =
      connection!.get(
        subscription_status_path(transaction_id)
      ) do |request|
        request.headers["Accept"] = "application/json"
        request.headers["Authorization"] = "Bearer #{authorization_token}"
      end

    parse_response(response)
  rescue Error
    raise
  rescue StandardError => error
    raise RequestFailed,
          "Apple App Store Server API request failed: #{error.message}"
  end

  private

  attr_reader :issuer_id,
              :key_id,
              :private_key_pem,
              :bundle_id,
              :environment,
              :http_environment,
              :clock

  def validate_configuration!
    raise ConfigurationError, "Apple issuer ID is not configured" if issuer_id.blank?
    raise ConfigurationError, "Apple key ID is not configured" if key_id.blank?

    if private_key_pem.blank?
      raise ConfigurationError,
            "Apple API private key is not configured"
    end

    raise ConfigurationError, "Apple bundle ID is not configured" if bundle_id.blank?

    unless %w[sandbox production].include?(environment)
      raise ConfigurationError,
            "Apple store environment must be sandbox or production"
    end

    signing_key!
  end

  def required_transaction_id!(value)
    transaction_id = value.to_s.strip
    return transaction_id if transaction_id.present?

    raise RequestFailed,
          "Apple original transaction ID is required"
  end

  def connection!
    @connection ||=
      Faraday.new(url: api_origin) do |faraday|
        faraday.options.open_timeout =
          StoreSubscriptionHttpConfiguration.open_timeout(
            environment: http_environment
          )

        faraday.options.timeout =
          StoreSubscriptionHttpConfiguration.read_timeout(
            environment: http_environment
          )
      end
  end

  def api_origin
    environment == "production" ? PRODUCTION_ORIGIN : SANDBOX_ORIGIN
  end

  def subscription_status_path(transaction_id)
    encoded_transaction_id =
      URI.encode_www_form_component(transaction_id)

    "/inApps/v1/subscriptions/#{encoded_transaction_id}"
  end

  def authorization_token
    issued_at = current_time.to_i

    payload = {
      "iss" => issuer_id,
      "iat" => issued_at,
      "exp" => issued_at + TOKEN_LIFETIME.to_i,
      "aud" => AUDIENCE,
      "bid" => bundle_id
    }

    headers = {
      "alg" => "ES256",
      "kid" => key_id,
      "typ" => "JWT"
    }

    JWT.encode(payload, signing_key!, "ES256", headers)
  rescue JWT::EncodeError, OpenSSL::PKey::PKeyError => error
    raise ConfigurationError,
          "Apple API authorization token could not be created: #{error.class.name}"
  end

  def current_time
    value = clock.call

    if value.respond_to?(:in_time_zone) && !value.is_a?(String)
      return value.in_time_zone
    end

    Time.zone.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    raise ConfigurationError,
          "Apple API clock did not return a valid timestamp"
  end

  def signing_key!
    return @signing_key if defined?(@signing_key)

    key_data = private_key_pem.gsub("\\n", "\n")
    key = OpenSSL::PKey.read(key_data)

    unless key.is_a?(OpenSSL::PKey::EC)
      raise ConfigurationError,
            "Apple API private key must be an EC key"
    end

    @signing_key = key
  rescue OpenSSL::PKey::PKeyError, ArgumentError => error
    raise ConfigurationError,
          "Apple API private key is invalid: #{error.class.name}"
  end

  def parse_response(response)
    status = response.status.to_i

    case status
    when 200..299
      parse_json(response.body)
    when 401, 403
      raise AuthenticationError,
            "Apple App Store Server API authentication failed (HTTP #{status})"
    when 404
      raise NotFound,
            "Apple subscription was not found"
    when 429
      raise RateLimited,
            "Apple App Store Server API rate limit was exceeded"
    when 500..599
      raise ServerError,
            "Apple App Store Server API is temporarily unavailable (HTTP #{status})"
    else
      raise RequestFailed,
            "Apple App Store Server API returned HTTP #{status}"
    end
  end

  def parse_json(body)
    payload = JSON.parse(body.to_s)

    unless payload.is_a?(Hash)
      raise RequestFailed,
            "Apple App Store Server API returned an invalid response"
    end

    payload
  rescue JSON::ParserError
    raise RequestFailed,
          "Apple App Store Server API returned invalid JSON"
  end
end
