require "json"
require "net/http"
require "uri"

class AppleAndroidAuthController < ApplicationController
  APPLE_TOKEN_URL =
    URI("https://appleid.apple.com/auth/token")

  def callback
    if params[:error].present?
      return redirect_to_app(
        error:
          params[:error_description].presence ||
          params[:error]
      )
    end

    code =
      params[:code]
        .to_s
        .strip

    if code.blank?
      return redirect_to_app(
        error:
          "Apple did not return an authorization code."
      )
    end

    token_response =
      exchange_code!(
        code
      )

    id_token =
      token_response[
        "id_token"
      ].to_s

    if id_token.blank?
      raise StandardError,
            "Apple did not return an identity token."
    end

    redirect_to_app(
      id_token: id_token,
      access_token:
        token_response[
          "access_token"
        ].to_s.presence
    )
  rescue StandardError => error
    Rails.logger.error(
      "[AppleAndroidAuth] #{error.class}: #{error.message}"
    )

    redirect_to_app(
      error:
        "Apple Sign-In could not be completed."
    )
  end

  private

  def exchange_code!(code)
    request =
      Net::HTTP::Post.new(
        APPLE_TOKEN_URL
      )

    request[
      "Content-Type"
    ] =
      "application/x-www-form-urlencoded"

    request.body =
      URI.encode_www_form(
        client_id:
          service_id,
        client_secret:
          client_secret,
        code: code,
        grant_type:
          "authorization_code",
        redirect_uri:
          redirect_uri
      )

    response =
      Net::HTTP.start(
        APPLE_TOKEN_URL.host,
        APPLE_TOKEN_URL.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 10
      ) do |http|
        http.request(
          request
        )
      end

    payload =
      JSON.parse(
        response.body
      )

    unless response.is_a?(
      Net::HTTPSuccess
    )
      raise StandardError,
            payload[
              "error_description"
            ].presence ||
            payload["error"].presence ||
            "Apple token exchange failed."
    end

    payload
  end

  def client_secret
    now =
      Time.current.to_i

    payload = {
      iss: team_id,
      iat: now,
      exp:
        now + 5.minutes.to_i,
      aud:
        "https://appleid.apple.com",
      sub: service_id
    }

    JWT.encode(
      payload,
      private_key,
      "ES256",
      {
        kid: key_id
      }
    )
  end

  def private_key
    raw =
      ENV
        .fetch(
          "APPLE_SIGN_IN_PRIVATE_KEY"
        )
        .gsub(
          "\\n",
          "\n"
        )

    OpenSSL::PKey::EC.new(
      raw
    )
  end

  def key_id
    ENV.fetch(
      "APPLE_SIGN_IN_KEY_ID"
    )
  end

  def team_id
    ENV.fetch(
      "APPLE_TEAM_ID"
    )
  end

  def service_id
    ENV.fetch(
      "APPLE_ANDROID_SERVICE_ID",
      "uk.matchmuster.mobile.service"
    )
  end

  def redirect_uri
    ENV.fetch(
      "APPLE_ANDROID_REDIRECT_URI",
      "https://matchmuster-82e714e1ef29.herokuapp.com/auth/apple/android/callback"
    )
  end

  def app_redirect_url
    ENV.fetch(
      "APPLE_ANDROID_APP_REDIRECT_URL",
      "matchmuster://apple-login"
    )
  end

  def redirect_to_app(
    id_token: nil,
    access_token: nil,
    error: nil
  )
    query = {}

    query[
      :id_token
    ] = id_token if id_token.present?

    query[
      :access_token
    ] = access_token if access_token.present?

    query[
      :error
    ] = error if error.present?

    destination =
      "#{app_redirect_url}?#{URI.encode_www_form(query)}"

    redirect_to(
      destination,
      allow_other_host: true
    )
  end
end
