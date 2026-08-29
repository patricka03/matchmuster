require "json"
require "net/http"
require "uri"
require "googleauth/id_tokens"

class SocialIdentityVerifier
  class VerificationError < StandardError; end

  APPLE_ISSUER = "https://appleid.apple.com".freeze
  APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys".freeze

  class << self
    def call(provider:, id_token:)
      provider = provider.to_s.downcase.strip

      case provider
      when "google"
        verify_google(id_token)
      when "apple"
        verify_apple(id_token)
      else
        raise VerificationError,
              "Unsupported sign-in provider."
      end
    rescue JWT::DecodeError,
           JWT::JWKError,
           Google::Auth::IDTokens::VerificationError,
           JSON::ParserError,
           OpenSSL::PKey::PKeyError => error
      raise VerificationError,
            "The #{provider} sign-in token could not be verified: #{error.message}"
    end

    private

    def verify_google(id_token)
      audiences =
        ENV
          .fetch(
            "GOOGLE_OAUTH_CLIENT_IDS",
            ""
          )
          .split(",")
          .map(&:strip)
          .reject(&:blank?)

      if audiences.empty?
        raise VerificationError,
              "Google Sign-In is not configured on the MatchMuster server."
      end

      payload = nil
      last_error = nil

      audiences.each do |audience|
        begin
          payload =
            Google::Auth::IDTokens.verify_oidc(
              id_token,
              aud: audience
            )
          break
        rescue Google::Auth::IDTokens::VerificationError => error
          last_error = error
        end
      end

      unless payload
        raise last_error ||
              VerificationError.new(
                "Google token audience did not match."
              )
      end

      ensure_verified_email!(payload)
      normalized_payload("google", payload)
    end

    def verify_apple(id_token)
      client_id =
        ENV.fetch(
          "APPLE_SIGN_IN_CLIENT_ID",
          "uk.matchmuster.mobile"
        )

      jwks =
        JWT::JWK::Set.new(
          apple_jwks
        )

      payload, =
        JWT.decode(
          id_token,
          nil,
          true,
          algorithms: ["RS256"],
          jwks: jwks,
          verify_iss: true,
          iss: APPLE_ISSUER,
          verify_aud: true,
          aud: client_id
        )

      ensure_verified_email!(payload) if payload["email"].present?
      normalized_payload("apple", payload)
    end

    def apple_jwks
      Rails.cache.fetch(
        "matchmuster/apple_sign_in_jwks",
        expires_in: 6.hours
      ) do
        response =
          Net::HTTP.get_response(
            URI(APPLE_JWKS_URL)
          )

        unless response.is_a?(Net::HTTPSuccess)
          raise VerificationError,
                "Apple public keys could not be loaded."
        end

        JSON.parse(response.body)
      end
    end

    def ensure_verified_email!(payload)
      verified =
        ActiveModel::Type::Boolean
          .new
          .cast(
            payload["email_verified"]
          )

      return if verified

      raise VerificationError,
            "The provider did not confirm ownership of this email address."
    end

    def normalized_payload(provider, payload)
      uid = payload["sub"].to_s.strip

      if uid.blank?
        raise VerificationError,
              "The provider did not return an account identifier."
      end

      {
        provider: provider,
        uid: uid,
        email:
          payload["email"]
            .to_s
            .downcase
            .strip
            .presence,
        claims: payload
      }
    end
  end
end
