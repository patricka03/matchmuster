require "base64"
require "json"
require "jwt"
require "openssl"

class AppleJwsVerifier
  class VerificationError < StandardError; end
  class InvalidToken < VerificationError; end
  class InvalidHeader < VerificationError; end
  class InvalidCertificate < VerificationError; end
  class InvalidSignature < VerificationError; end

  ALGORITHM =
    "ES256"

  CERTIFICATE_CHAIN_LENGTH =
    3

  def initialize(
    certificate_chain_verifier:
  )
    @certificate_chain_verifier =
      certificate_chain_verifier
  end

  def verify(signed_payload)
    signed_payload =
      signed_payload.to_s.strip

    segments =
      token_segments!(
        signed_payload
      )

    header =
      decoded_segment!(
        segments.fetch(0),
        description:
          "header"
      )

    validate_header!(
      header
    )

    certificates =
      certificates_from!(
        header
      )

    unverified_payload =
      decoded_segment!(
        segments.fetch(1),
        description:
          "payload"
      )

    effective_at =
      signed_date_from!(
        unverified_payload
      )

    public_key =
      certificate_chain_verifier.verify(
        leaf_certificate:
          certificates.fetch(0),
        intermediate_certificate:
          certificates.fetch(1),
        presented_root_certificate:
          certificates.fetch(2),
        effective_at:
          effective_at
      )

    verified_payload =
      decode_verified_payload!(
        signed_payload,
        public_key
      )

    unless verified_payload.is_a?(Hash)
      raise InvalidToken,
            "Verified Apple JWS payload must be an object"
    end

    verified_payload.deep_stringify_keys
  end

  private

  attr_reader :certificate_chain_verifier

  def token_segments!(signed_payload)
    if signed_payload.blank?
      raise InvalidToken,
            "Apple signed payload is missing"
    end

    segments =
      signed_payload.split(
        ".",
        -1
      )

    valid =
      segments.length == 3 &&
      segments.all?(
        &:present?
      )

    return segments if valid

    raise InvalidToken,
          "Apple signed payload is not a valid compact JWS"
  end

  def decoded_segment!(
    encoded_segment,
    description:
  )
    decoded =
      Base64.urlsafe_decode64(
        padded_base64(
          encoded_segment
        )
      )

    payload =
      JSON.parse(
        decoded
      )

    unless payload.is_a?(Hash)
      raise InvalidToken,
            "Apple JWS #{description} must be an object"
    end

    payload.deep_stringify_keys

  rescue JSON::ParserError,
         ArgumentError => error

    raise InvalidToken,
          "Apple JWS #{description} is invalid: #{error.message}"
  end

  def padded_base64(value)
    value +
      (
        "=" *
        (
          (
            4 -
            value.length % 4
          ) % 4
        )
      )
  end

  def validate_header!(header)
    algorithm =
      header[
        "alg"
      ].to_s

    unless algorithm ==
           ALGORITHM

      raise InvalidHeader,
            "Apple JWS algorithm must be ES256"
    end

    chain =
      header[
        "x5c"
      ]

    unless chain.is_a?(Array) &&
           chain.length ==
             CERTIFICATE_CHAIN_LENGTH

      raise InvalidHeader,
            "Apple JWS certificate chain must contain three certificates"
    end
  end

  def certificates_from!(header)
    header
      .fetch(
        "x5c"
      )
      .map do |encoded_certificate|
        certificate_from!(
          encoded_certificate
        )
      end
  end

  def certificate_from!(encoded_certificate)
    certificate_data =
      Base64.strict_decode64(
        encoded_certificate.to_s
      )

    OpenSSL::X509::Certificate.new(
      certificate_data
    )

  rescue ArgumentError,
         OpenSSL::X509::CertificateError =>
           error

    raise InvalidCertificate,
          "Apple JWS certificate is invalid: #{error.message}"
  end

  def signed_date_from!(payload)
    milliseconds =
      payload[
        "signedDate"
      ].to_s.strip

    unless milliseconds.match?(
      /\A\d+\z/
    )
      raise InvalidToken,
            "Apple JWS signed date is invalid"
    end

    Time.at(
      milliseconds.to_i /
        1000.0
    ).utc
  end

  def decode_verified_payload!(
    signed_payload,
    public_key
  )
    payload, =
      JWT.decode(
        signed_payload,
        public_key,
        true,
        {
          algorithm:
            ALGORITHM
        }
      )

    payload

  rescue JWT::DecodeError => error
    raise InvalidSignature,
          "Apple JWS signature verification failed: #{error.message}"
  end
end
