require "test_helper"

class AppleSignedDataVerifierTest <
    ActiveSupport::TestCase
  BUNDLE_ID =
    "uk.matchmuster.app"

  APP_APPLE_ID =
    "1234567890"

  class FakeJwsVerifier
    attr_reader :calls

    def initialize(
      payloads: {},
      error: nil
    )
      @payloads =
        payloads

      @error =
        error

      @calls = []
    end

    def verify(signed_payload)
      @calls << signed_payload

      raise @error if @error

      @payloads.fetch(
        signed_payload
      )
    end
  end

  test "validates sandbox notification" do
    payload = {
      "notificationType" =>
        "SUBSCRIBED",

      "data" => {
        "bundleId" =>
          BUNDLE_ID,

        "environment" =>
          "Sandbox",

        "appAppleId" =>
          APP_APPLE_ID
      }
    }

    jws_verifier =
      fake_verifier(
        "signed-notification" =>
          payload
      )

    verifier =
      build_verifier(
        jws_verifier:
          jws_verifier
      )

    result =
      verifier.verify_notification(
        "signed-notification"
      )

    assert_equal(
      payload,
      result
    )

    assert_equal(
      [
        "signed-notification"
      ],
      jws_verifier.calls
    )
  end

  test "validates transaction bundle and environment" do
    payload = {
      "bundleId" =>
        BUNDLE_ID,

      "environment" =>
        "Sandbox",

      "originalTransactionId" =>
        "apple-original-transaction"
    }

    verifier =
      build_verifier(
        jws_verifier:
          fake_verifier(
            "signed-transaction" =>
              payload
          )
      )

    result =
      verifier.verify_transaction(
        "signed-transaction"
      )

    assert_equal(
      "apple-original-transaction",
      result.fetch(
        "originalTransactionId"
      )
    )
  end

  test "validates renewal information environment" do
    payload = {
      "environment" =>
        "Sandbox",

      "autoRenewStatus" => 1
    }

    verifier =
      build_verifier(
        jws_verifier:
          fake_verifier(
            "signed-renewal" =>
              payload
          )
      )

    result =
      verifier.verify_renewal_info(
        "signed-renewal"
      )

    assert_equal(
      1,
      result.fetch(
        "autoRenewStatus"
      )
    )
  end

  test "rejects incorrect bundle ID" do
    payload = {
      "data" => {
        "bundleId" =>
          "com.fake.application",

        "environment" =>
          "Sandbox"
      }
    }

    verifier =
      build_verifier(
        jws_verifier:
          fake_verifier(
            "signed-notification" =>
              payload
          )
      )

    assert_raises(
      AppleSignedDataVerifier::
        InvalidAppIdentifier
    ) do
      verifier.verify_notification(
        "signed-notification"
      )
    end
  end

  test "rejects incorrect environment" do
    payload = {
      "bundleId" =>
        BUNDLE_ID,

      "environment" =>
        "Production"
    }

    verifier =
      build_verifier(
        jws_verifier:
          fake_verifier(
            "signed-transaction" =>
              payload
          )
      )

    assert_raises(
      AppleSignedDataVerifier::
        InvalidEnvironment
    ) do
      verifier.verify_transaction(
        "signed-transaction"
      )
    end
  end

  test "requires Apple app ID in production" do
    error =
      assert_raises(
        AppleSignedDataVerifier::
          ConfigurationError
      ) do
        build_verifier(
          jws_verifier:
            fake_verifier,
          environment:
            "production",
          app_apple_id:
            nil
        )
      end

    assert_includes(
      error.message,
      "app ID is required"
    )
  end

  test "rejects incorrect production Apple app ID" do
    payload = {
      "data" => {
        "bundleId" =>
          BUNDLE_ID,

        "environment" =>
          "Production",

        "appAppleId" =>
          "9999999999"
      }
    }

    verifier =
      build_verifier(
        jws_verifier:
          fake_verifier(
            "signed-notification" =>
              payload
          ),
        environment:
          "production",
        app_apple_id:
          APP_APPLE_ID
      )

    assert_raises(
      AppleSignedDataVerifier::
        InvalidAppIdentifier
    ) do
      verifier.verify_notification(
        "signed-notification"
      )
    end
  end

  test "rejects non object verified payload" do
    verifier =
      build_verifier(
        jws_verifier:
          fake_verifier(
            "signed-notification" =>
              "invalid-payload"
          )
      )

    assert_raises(
      AppleSignedDataVerifier::
        InvalidPayload
    ) do
      verifier.verify_notification(
        "signed-notification"
      )
    end
  end

  test "does not hide JWS verification errors" do
    jws_verifier =
      FakeJwsVerifier.new(
        error:
          RuntimeError.new(
            "certificate verification failed"
          )
      )

    verifier =
      build_verifier(
        jws_verifier:
          jws_verifier
      )

    error =
      assert_raises(
        RuntimeError
      ) do
        verifier.verify_notification(
          "signed-notification"
        )
      end

    assert_equal(
      "certificate verification failed",
      error.message
    )
  end

  private

  def build_verifier(
    jws_verifier:,
    environment: "sandbox",
    app_apple_id: nil
  )
    AppleSignedDataVerifier.new(
      jws_verifier:
        jws_verifier,
      bundle_id:
        BUNDLE_ID,
      environment:
        environment,
      app_apple_id:
        app_apple_id
    )
  end

  def fake_verifier(payloads = {})
    FakeJwsVerifier.new(
      payloads:
        payloads
    )
  end
end
