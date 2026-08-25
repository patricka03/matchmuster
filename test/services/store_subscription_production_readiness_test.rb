require "test_helper"
require "base64"
require "json"
require "openssl"

class StoreSubscriptionProductionReadinessTest < ActiveSupport::TestCase
  setup do
    @apple_key = OpenSSL::PKey::EC.generate("prime256v1")
    @google_key = OpenSSL::PKey::RSA.new(2048)
  end

  test "accepts complete production configuration" do
    result =
      StoreSubscriptionProductionReadiness.call(
        environment: complete_environment
      )

    assert_equal(true, result.fetch(:ok))
    assert_equal(
      "production",
      result.fetch(:apple_environment)
    )
    assert_equal(
      "environment_json",
      result.fetch(:google_credentials)
    )
  end

  test "collects missing configuration without exposing values" do
    environment = {
      "FRONTEND_URL" => "http://frontend.example.com",
      "APPLE_PRIVATE_KEY" => "super-secret-key",
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" => "not-json"
    }

    error =
      assert_raises(
        StoreSubscriptionProductionReadiness::ConfigurationError
      ) do
        StoreSubscriptionProductionReadiness.call(
          environment: environment
        )
      end

    assert_operator(error.problems.length, :>, 5)
    assert_includes(error.message, "FRONTEND_URL")
    assert_includes(error.message, "APPLE_BUNDLE_ID")
    assert_includes(error.message, "GOOGLE_PLAY_PACKAGE_NAME")

    refute_includes(error.message, "super-secret-key")
  end

  test "rejects an invalid Apple environment and app ID" do
    environment = complete_environment.merge(
      "APPLE_STORE_ENVIRONMENT" => "live",
      "APPLE_APP_ID" => "not-numeric"
    )

    error =
      assert_raises(
        StoreSubscriptionProductionReadiness::ConfigurationError
      ) do
        StoreSubscriptionProductionReadiness.call(
          environment: environment
        )
      end

    assert_includes(error.message, "sandbox or production")
    assert_includes(error.message, "digits only")
  end

  test "accepts application default Google credentials path" do
    environment = complete_environment
      .except("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
      .merge(
        "GOOGLE_APPLICATION_CREDENTIALS" =>
          "/run/secrets/google-service-account.json"
      )

    result =
      StoreSubscriptionProductionReadiness.call(
        environment: environment
      )

    assert_equal(
      "application_default_credentials",
      result.fetch(:google_credentials)
    )
  end

  private

  def complete_environment
    {
      "FRONTEND_URL" => "https://app.matchmuster.uk",
      "APPLE_BUNDLE_ID" => "uk.matchmuster.app",
      "APPLE_STORE_ENVIRONMENT" => "production",
      "APPLE_APP_ID" => "1234567890",
      "APPLE_ISSUER_ID" => "issuer-id",
      "APPLE_KEY_ID" => "KEY1234567",
      "APPLE_PRIVATE_KEY" => @apple_key.private_to_pem,
      "APPLE_ROOT_CERTIFICATES_BASE64" =>
        Base64.strict_encode64(root_certificate.to_der),
      "GOOGLE_PLAY_PACKAGE_NAME" => "uk.matchmuster.app",
      "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON" =>
        JSON.generate(
          "type" => "service_account",
          "project_id" => "matchmuster-production",
          "private_key_id" => "google-key-id",
          "private_key" => @google_key.to_pem,
          "client_email" =>
            "subscriptions@matchmuster-production.iam.gserviceaccount.com",
          "token_uri" => "https://oauth2.googleapis.com/token"
        )
    }
  end

  def root_certificate
    key = OpenSSL::PKey::RSA.new(2048)

    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject =
      OpenSSL::X509::Name.parse("/CN=MatchMuster Test Root")
    certificate.issuer = certificate.subject
    certificate.public_key = key.public_key
    certificate.not_before = Time.current - 1.day
    certificate.not_after = Time.current + 1.year

    extension_factory = OpenSSL::X509::ExtensionFactory.new
    extension_factory.subject_certificate = certificate
    extension_factory.issuer_certificate = certificate

    certificate.add_extension(
      extension_factory.create_extension(
        "basicConstraints",
        "CA:TRUE",
        true
      )
    )

    certificate.sign(key, OpenSSL::Digest::SHA256.new)
    certificate
  end
end
