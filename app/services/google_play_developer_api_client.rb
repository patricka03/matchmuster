require "faraday"
require "googleauth"
require "json"
require "uri"

class GooglePlayDeveloperApiClient
  API_ORIGIN =
    "https://androidpublisher.googleapis.com"

  ANDROID_PUBLISHER_SCOPE =
    "https://www.googleapis.com/auth/androidpublisher"

  class Error < StandardError; end
  class AuthenticationError < Error; end
  class NotFound < Error; end
  class RequestFailed < Error; end

  def initialize(
    connection: nil,
    credentials: nil
  )
    @connection =
      connection ||
      Faraday.new(
        url: API_ORIGIN
      )

    @credentials =
      credentials ||
      Google::Auth.get_application_default(
        [
          ANDROID_PUBLISHER_SCOPE
        ]
      )
  end

  def fetch_subscription(
    package_name:,
    purchase_token:
  )
    response =
      connection.get(
        subscription_path(
          package_name: package_name,
          purchase_token: purchase_token
        )
      ) do |request|
        request.headers["Accept"] =
          "application/json"

        request.headers["Authorization"] =
          "Bearer #{access_token}"
      end

    parse_response(response)
  rescue Error
    raise
  rescue StandardError => error
    raise RequestFailed,
          "Google Play request failed: #{error.message}"
  end

  private

  attr_reader :connection,
              :credentials

  def subscription_path(
    package_name:,
    purchase_token:
  )
    encoded_package_name =
      URI.encode_www_form_component(
        package_name.to_s
      )

    encoded_purchase_token =
      URI.encode_www_form_component(
        purchase_token.to_s
      )

    [
      "/androidpublisher/v3/applications",
      encoded_package_name,
      "purchases/subscriptionsv2/tokens",
      encoded_purchase_token
    ].join("/")
  end

  def access_token
    token_response =
      credentials.fetch_access_token!

    token =
      token_response["access_token"] ||
      token_response[:access_token]

    if token.to_s.empty?
      raise AuthenticationError,
            "Google credentials did not return an access token"
    end

    token
  rescue AuthenticationError
    raise
  rescue StandardError => error
    raise AuthenticationError,
          "Google authentication failed: #{error.message}"
  end

  def parse_response(response)
    status =
      response.status.to_i

    case status
    when 200..299
      parse_json(response.body)
    when 401, 403
      raise AuthenticationError,
            "Google Play authentication failed (HTTP #{status})"
    when 404
      raise NotFound,
            "Google Play subscription was not found"
    else
      raise RequestFailed,
            "Google Play API returned HTTP #{status}"
    end
  end

  def parse_json(body)
    payload =
      JSON.parse(
        body.to_s
      )

    unless payload.is_a?(Hash)
      raise RequestFailed,
            "Google Play returned an invalid response"
    end

    payload
  rescue JSON::ParserError => error
    raise RequestFailed,
          "Google Play returned invalid JSON: #{error.message}"
  end
end
