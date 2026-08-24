require "base64"
require "openssl"

class AppleSignedDataVerifierFactory
  class ConfigurationError <
    AppleSignedDataVerifier::ConfigurationError
  end

  class << self
    def build
      new.build
    end
  end

  def initialize(
    bundle_id:
      ENV[
        "APPLE_BUNDLE_ID"
      ],
    environment:
      ENV[
        "APPLE_STORE_ENVIRONMENT"
      ],
    app_apple_id:
      ENV[
        "APPLE_APP_ID"
      ],
    root_certificates_base64:
      ENV[
        "APPLE_ROOT_CERTIFICATES_BASE64"
      ]
  )
    @bundle_id =
      bundle_id

    @environment =
      environment

    @app_apple_id =
      app_apple_id

    @root_certificates_base64 =
      root_certificates_base64
  end

  def build
    certificate_chain_verifier =
      AppleCertificateChainVerifier.new(
        trusted_root_certificates:
          trusted_root_certificates!
      )

    jws_verifier =
      AppleJwsVerifier.new(
        certificate_chain_verifier:
          certificate_chain_verifier
      )

    AppleSignedDataVerifier.new(
      jws_verifier:
        jws_verifier,
      bundle_id:
        bundle_id,
      environment:
        environment,
      app_apple_id:
        app_apple_id
    )
  end

  private

  attr_reader :bundle_id,
              :environment,
              :app_apple_id,
              :root_certificates_base64

  def trusted_root_certificates!
    encoded_certificates =
      root_certificates_base64
        .to_s
        .split(
          ","
        )
        .map(
          &:strip
        )
        .reject(
          &:blank?
        )

    if encoded_certificates.empty?
      raise ConfigurationError,
            "Apple trusted root certificates are not configured"
    end

    encoded_certificates.map.with_index do |
      encoded_certificate,
      index
    |
      decode_certificate!(
        encoded_certificate,
        index:
          index
      )
    end
  end

  def decode_certificate!(
    encoded_certificate,
    index:
  )
    certificate_data =
      Base64.strict_decode64(
        encoded_certificate
      )

    OpenSSL::X509::Certificate.new(
      certificate_data
    )

  rescue ArgumentError,
         OpenSSL::X509::CertificateError =>
           error

    raise ConfigurationError,
          "Apple trusted root certificate " \
          "#{index + 1} is invalid: #{error.message}"
  end
end
