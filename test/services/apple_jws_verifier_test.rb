require "test_helper"
require "base64"
require "jwt"
require "openssl"

class AppleJwsVerifierTest <
    ActiveSupport::TestCase
  class FakeCertificateChainVerifier
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = []
    end

    def verify(
      leaf_certificate:,
      intermediate_certificate:,
      presented_root_certificate:,
      effective_at:
    )
      @calls << {
        leaf_certificate:
          leaf_certificate,
        intermediate_certificate:
          intermediate_certificate,
        presented_root_certificate:
          presented_root_certificate,
        effective_at:
          effective_at
      }

      raise @error if @error

      leaf_certificate.public_key
    end
  end

  setup do
    @signed_at =
      Time.utc(
        2026,
        9,
        1,
        12,
        0,
        0
      )

    @private_key =
      OpenSSL::PKey::EC.generate(
        "prime256v1"
      )

    @certificate =
      self_signed_certificate(
        @private_key
      )

    @certificate_chain =
      Array.new(
        3,
        Base64.strict_encode64(
          @certificate.to_der
        )
      )
  end

  test "verifies signed ES256 payload" do
    payload =
      valid_payload

    chain_verifier =
      FakeCertificateChainVerifier.new

    verifier =
      build_verifier(
        chain_verifier
      )

    result =
      verifier.verify(
        signed_token(
          payload
        )
      )

    assert_equal(
      payload,
      result
    )

    assert_equal(
      1,
      chain_verifier.calls.length
    )

    call =
      chain_verifier.calls.first

    assert_instance_of(
      OpenSSL::X509::Certificate,
      call.fetch(
        :leaf_certificate
      )
    )

    assert_instance_of(
      OpenSSL::X509::Certificate,
      call.fetch(
        :intermediate_certificate
      )
    )

    assert_instance_of(
      OpenSSL::X509::Certificate,
      call.fetch(
        :presented_root_certificate
      )
    )

    assert_equal(
      @signed_at,
      call.fetch(
        :effective_at
      )
    )
  end

  test "rejects algorithm other than ES256" do
    token =
      JWT.encode(
        valid_payload,
        "not-an-apple-key",
        "HS256",
        {
          "x5c" =>
            @certificate_chain
        }
      )

    error =
      assert_raises(
        AppleJwsVerifier::
          InvalidHeader
      ) do
        build_verifier.verify(
          token
        )
      end

    assert_includes(
      error.message,
      "algorithm must be ES256"
    )
  end

  test "requires exactly three certificates" do
    token =
      signed_token(
        valid_payload,
        certificate_chain:
          [
            @certificate_chain.first
          ]
      )

    error =
      assert_raises(
        AppleJwsVerifier::
          InvalidHeader
      ) do
        build_verifier.verify(
          token
        )
      end

    assert_includes(
      error.message,
      "three certificates"
    )
  end

  test "rejects invalid certificate data" do
    chain =
      @certificate_chain.dup

    chain[0] =
      Base64.strict_encode64(
        "not-a-certificate"
      )

    token =
      signed_token(
        valid_payload,
        certificate_chain:
          chain
      )

    assert_raises(
      AppleJwsVerifier::
        InvalidCertificate
    ) do
      build_verifier.verify(
        token
      )
    end
  end

  test "rejects malformed compact JWS" do
    assert_raises(
      AppleJwsVerifier::
        InvalidToken
    ) do
      build_verifier.verify(
        "not-a-compact-jws"
      )
    end
  end

  test "rejects missing signed date" do
    payload =
      valid_payload

    payload.delete(
      "signedDate"
    )

    error =
      assert_raises(
        AppleJwsVerifier::
          InvalidToken
      ) do
        build_verifier.verify(
          signed_token(
            payload
          )
        )
      end

    assert_includes(
      error.message,
      "signed date is invalid"
    )
  end

  test "rejects tampered signature" do
    token =
      signed_token(
        valid_payload
      )

    segments =
      token.split(
        "."
      )

    signature =
      segments.fetch(2)

    replacement =
      signature.start_with?(
        "A"
      ) ? "B" : "A"

    segments[2] =
      replacement +
      signature[
        1..
      ]

    tampered_token =
      segments.join(
        "."
      )

    assert_raises(
      AppleJwsVerifier::
        InvalidSignature
    ) do
      build_verifier.verify(
        tampered_token
      )
    end
  end

  test "does not hide certificate chain errors" do
    chain_verifier =
      FakeCertificateChainVerifier.new(
        error:
          RuntimeError.new(
            "certificate chain is not trusted"
          )
      )

    error =
      assert_raises(
        RuntimeError
      ) do
        build_verifier(
          chain_verifier
        ).verify(
          signed_token(
            valid_payload
          )
        )
      end

    assert_equal(
      "certificate chain is not trusted",
      error.message
    )
  end

  private

  def build_verifier(
    chain_verifier =
      FakeCertificateChainVerifier.new
  )
    AppleJwsVerifier.new(
      certificate_chain_verifier:
        chain_verifier
    )
  end

  def valid_payload
    {
      "notificationType" =>
        "SUBSCRIBED",

      "signedDate" =>
        milliseconds(
          @signed_at
        ),

      "data" => {
        "bundleId" =>
          "uk.matchmuster.app",

        "environment" =>
          "Sandbox"
      }
    }
  end

  def signed_token(
    payload,
    certificate_chain:
      @certificate_chain
  )
    JWT.encode(
      payload,
      @private_key,
      "ES256",
      {
        "x5c" =>
          certificate_chain
      }
    )
  end

  def self_signed_certificate(key)
    certificate =
      OpenSSL::X509::Certificate.new

    certificate.version = 2
    certificate.serial = 1

    certificate.subject =
      OpenSSL::X509::Name.parse(
        "/CN=Apple JWS Test Leaf"
      )

    certificate.issuer =
      certificate.subject

    certificate.public_key =
      key

    certificate.not_before =
      @signed_at - 1.day

    certificate.not_after =
      @signed_at + 1.day

    extension_factory =
      OpenSSL::X509::ExtensionFactory.new

    extension_factory
      .subject_certificate =
        certificate

    extension_factory
      .issuer_certificate =
        certificate

    certificate.add_extension(
      extension_factory.create_extension(
        "basicConstraints",
        "CA:FALSE",
        true
      )
    )

    certificate.add_extension(
      extension_factory.create_extension(
        "keyUsage",
        "digitalSignature",
        true
      )
    )

    certificate.sign(
      key,
      OpenSSL::Digest::SHA256.new
    )

    certificate
  end

  def milliseconds(time)
    (
      time.to_f *
      1000
    ).to_i
  end
end
