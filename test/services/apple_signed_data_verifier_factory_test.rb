require "test_helper"
require "base64"
require "openssl"

class AppleSignedDataVerifierFactoryTest <
    ActiveSupport::TestCase
  BUNDLE_ID =
    "uk.matchmuster.app"

  APP_APPLE_ID =
    "1234567890"

  setup do
    @root_certificate =
      create_root_certificate

    @encoded_root =
      Base64.strict_encode64(
        @root_certificate.to_der
      )
  end

  test "builds sandbox signed data verifier" do
    verifier =
      build_factory.build

    assert_instance_of(
      AppleSignedDataVerifier,
      verifier
    )
  end

  test "accepts multiple trusted roots" do
    second_root =
      create_root_certificate(
        serial: 2,
        common_name:
          "Second Apple Test Root"
      )

    encoded_roots = [
      @encoded_root,
      Base64.strict_encode64(
        second_root.to_der
      )
    ].join(
      ","
    )

    verifier =
      build_factory(
        root_certificates_base64:
          encoded_roots
      ).build

    assert_instance_of(
      AppleSignedDataVerifier,
      verifier
    )
  end

  test "builds production verifier with Apple app ID" do
    verifier =
      build_factory(
        environment:
          "production",
        app_apple_id:
          APP_APPLE_ID
      ).build

    assert_instance_of(
      AppleSignedDataVerifier,
      verifier
    )
  end

  test "requires trusted root certificates" do
    error =
      assert_raises(
        AppleSignedDataVerifierFactory::
          ConfigurationError
      ) do
        build_factory(
          root_certificates_base64:
            nil
        ).build
      end

    assert_includes(
      error.message,
      "not configured"
    )
  end

  test "rejects invalid base64 certificate" do
    assert_raises(
      AppleSignedDataVerifierFactory::
        ConfigurationError
    ) do
      build_factory(
        root_certificates_base64:
          "not-valid-base64"
      ).build
    end
  end

  test "rejects decoded data that is not certificate" do
    encoded =
      Base64.strict_encode64(
        "not-an-x509-certificate"
      )

    assert_raises(
      AppleSignedDataVerifierFactory::
        ConfigurationError
    ) do
      build_factory(
        root_certificates_base64:
          encoded
      ).build
    end
  end

  test "requires bundle ID" do
    assert_raises(
      AppleSignedDataVerifier::
        ConfigurationError
    ) do
      build_factory(
        bundle_id: nil
      ).build
    end
  end

  test "requires production Apple app ID" do
    assert_raises(
      AppleSignedDataVerifier::
        ConfigurationError
    ) do
      build_factory(
        environment:
          "production",
        app_apple_id:
          nil
      ).build
    end
  end

  private

  def build_factory(
    bundle_id: BUNDLE_ID,
    environment: "sandbox",
    app_apple_id: nil,
    root_certificates_base64:
      @encoded_root
  )
    AppleSignedDataVerifierFactory.new(
      bundle_id:
        bundle_id,
      environment:
        environment,
      app_apple_id:
        app_apple_id,
      root_certificates_base64:
        root_certificates_base64
    )
  end

  def create_root_certificate(
    serial: 1,
    common_name:
      "Apple Test Root"
  )
    key =
      OpenSSL::PKey::EC.generate(
        "prime256v1"
      )

    certificate =
      OpenSSL::X509::Certificate.new

    certificate.version = 2
    certificate.serial =
      serial

    certificate.subject =
      OpenSSL::X509::Name.parse(
        "/CN=#{common_name}"
      )

    certificate.issuer =
      certificate.subject

    certificate.public_key =
      OpenSSL::PKey.read(
        key.public_to_der
      )

    certificate.not_before =
      Time.current - 1.day

    certificate.not_after =
      Time.current + 10.years

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
        "CA:TRUE",
        true
      )
    )

    certificate.add_extension(
      extension_factory.create_extension(
        "keyUsage",
        "keyCertSign, cRLSign",
        true
      )
    )

    certificate.sign(
      key,
      OpenSSL::Digest::SHA256.new
    )

    certificate
  end
end
