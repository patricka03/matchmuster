require "test_helper"
require "json"
require "jwt"
require "openssl"

class AppleAppStoreServerApiClientTest <
  ActiveSupport::TestCase

  FakeResponse =
    Struct.new(
      :status,
      :body,
      keyword_init: true
    )

  class FakeRequest
    attr_reader :headers

    def initialize
      @headers = {}
    end
  end

  class FakeConnection
    attr_reader :requests

    def initialize(response:)
      @response =
        response

      @requests = []
    end

    def get(path)
      request =
        FakeRequest.new

      yield request

      requests << {
        path: path,
        headers:
          request.headers.deep_dup
      }

      @response
    end
  end

  setup do
    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @signing_key =
      OpenSSL::PKey::EC.generate(
        "prime256v1"
      )

    @private_key_pem =
      @signing_key.private_to_pem

    @success_payload = {
      "environment" =>
        "Sandbox",
      "bundleId" =>
        "uk.matchmuster.app",
      "data" => []
    }
  end

  test "fetches Apple subscription status with signed authorization" do
    connection =
      fake_connection(
        status: 200,
        body:
          JSON.generate(
            @success_payload
          )
      )

    result =
      build_client(
        connection: connection
      ).fetch_subscription_status(
        original_transaction_id:
          "apple transaction/123"
      )

    assert_equal(
      @success_payload,
      result
    )

    request =
      connection.requests.fetch(
        0
      )

    assert_equal(
      "/inApps/v1/subscriptions/apple+transaction%2F123",
      request.fetch(
        :path
      )
    )

    assert_equal(
      "application/json",
      request
        .fetch(
          :headers
        )
        .fetch(
          "Accept"
        )
    )

    assert_match(
      /\ABearer /,
      request
        .fetch(
          :headers
        )
        .fetch(
          "Authorization"
        )
    )
  end

  test "authorization token contains required Apple claims" do
    connection =
      fake_connection(
        status: 200,
        body:
          JSON.generate(
            @success_payload
          )
      )

    build_client(
      connection: connection
    ).fetch_subscription_status(
      original_transaction_id:
        "2000000123456789"
    )

    authorization =
      connection
        .requests
        .fetch(
          0
        )
        .fetch(
          :headers
        )
        .fetch(
          "Authorization"
        )

    token =
      authorization.delete_prefix(
        "Bearer "
      )

    payload,
      header =
        JWT.decode(
          token,
          nil,
          false
        )

    assert_equal(
      "issuer-123",
      payload.fetch(
        "iss"
      )
    )

    assert_equal(
      AppleAppStoreServerApiClient::
        AUDIENCE,
      payload.fetch(
        "aud"
      )
    )

    assert_equal(
      "uk.matchmuster.app",
      payload.fetch(
        "bid"
      )
    )

    assert_equal(
      @now.to_i,
      payload.fetch(
        "iat"
      )
    )

    assert_equal(
      @now.to_i + 5.minutes.to_i,
      payload.fetch(
        "exp"
      )
    )

    assert_equal(
      "key-123",
      header.fetch(
        "kid"
      )
    )

    assert_equal(
      "ES256",
      header.fetch(
        "alg"
      )
    )
  end

  test "accepts private key with escaped newlines" do
    escaped_private_key =
      @private_key_pem.gsub(
        "\n",
        "\\n"
      )

    connection =
      fake_connection(
        status: 200,
        body:
          JSON.generate(
            @success_payload
          )
      )

    result =
      build_client(
        connection: connection,
        private_key:
          escaped_private_key
      ).fetch_subscription_status(
        original_transaction_id:
          "2000000123456789"
      )

    assert_equal(
      @success_payload,
      result
    )
  end

  test "requires original transaction ID" do
    connection =
      fake_connection(
        status: 200,
        body: "{}"
      )

    error =
      assert_raises(
        AppleAppStoreServerApiClient::
          RequestFailed
      ) do
        build_client(
          connection: connection
        ).fetch_subscription_status(
          original_transaction_id: nil
        )
      end

    assert_includes(
      error.message,
      "transaction ID"
    )

    assert_empty(
      connection.requests
    )
  end

  test "requires issuer ID" do
    assert_configuration_error(
      "issuer ID",
      issuer_id: nil
    )
  end

  test "requires key ID" do
    assert_configuration_error(
      "key ID",
      key_id: nil
    )
  end

  test "requires private key" do
    assert_configuration_error(
      "private key",
      private_key: nil
    )
  end

  test "rejects invalid private key" do
    assert_configuration_error(
      "private key is invalid",
      private_key:
        "not-a-private-key"
    )
  end

  test "requires bundle ID" do
    assert_configuration_error(
      "bundle ID",
      bundle_id: nil
    )
  end

  test "requires supported store environment" do
    assert_configuration_error(
      "sandbox or production",
      environment:
        "another-environment"
    )
  end

  test "classifies Apple authentication failure" do
    assert_response_error(
      status: 401,
      error_class:
        AppleAppStoreServerApiClient::
          AuthenticationError,
      message:
        "authentication failed"
    )
  end

  test "classifies missing Apple subscription" do
    assert_response_error(
      status: 404,
      error_class:
        AppleAppStoreServerApiClient::
          NotFound,
      message:
        "not found"
    )
  end

  test "classifies Apple rate limit" do
    assert_response_error(
      status: 429,
      error_class:
        AppleAppStoreServerApiClient::
          RateLimited,
      message:
        "rate limit"
    )
  end

  test "classifies unexpected Apple response" do
    assert_response_error(
      status: 503,
      error_class:
        AppleAppStoreServerApiClient::
          RequestFailed,
      message:
        "HTTP 503"
    )
  end

  test "rejects invalid response JSON" do
    connection =
      fake_connection(
        status: 200,
        body:
          "not-json"
      )

    error =
      assert_raises(
        AppleAppStoreServerApiClient::
          RequestFailed
      ) do
        build_client(
          connection: connection
        ).fetch_subscription_status(
          original_transaction_id:
            "2000000123456789"
        )
      end

    assert_includes(
      error.message,
      "invalid JSON"
    )
  end

  test "rejects non-object response JSON" do
    connection =
      fake_connection(
        status: 200,
        body:
          "[]"
      )

    error =
      assert_raises(
        AppleAppStoreServerApiClient::
          RequestFailed
      ) do
        build_client(
          connection: connection
        ).fetch_subscription_status(
          original_transaction_id:
            "2000000123456789"
        )
      end

    assert_includes(
      error.message,
      "invalid response"
    )
  end

  test "rejects invalid clock value before request" do
    connection =
      fake_connection(
        status: 200,
        body: "{}"
      )

    error =
      assert_raises(
        AppleAppStoreServerApiClient::
          ConfigurationError
      ) do
        build_client(
          connection: connection,
          clock:
            -> {
              "not-a-time"
            }
        ).fetch_subscription_status(
          original_transaction_id:
            "2000000123456789"
        )
      end

    assert_includes(
      error.message,
      "valid timestamp"
    )

    assert_empty(
      connection.requests
    )
  end

  private

  def build_client(
    connection:,
    issuer_id: "issuer-123",
    key_id: "key-123",
    private_key: @private_key_pem,
    bundle_id: "uk.matchmuster.app",
    environment: "sandbox",
    clock:
      -> {
        @now
      }
  )
    AppleAppStoreServerApiClient.new(
      connection: connection,
      issuer_id: issuer_id,
      key_id: key_id,
      private_key: private_key,
      bundle_id: bundle_id,
      environment: environment,
      clock: clock
    )
  end

  def fake_connection(
    status:,
    body:
  )
    FakeConnection.new(
      response:
        FakeResponse.new(
          status: status,
          body: body
        )
    )
  end

  def assert_configuration_error(
    message,
    **overrides
  )
    connection =
      fake_connection(
        status: 200,
        body: "{}"
      )

    error =
      assert_raises(
        AppleAppStoreServerApiClient::
          ConfigurationError
      ) do
        build_client(
          connection: connection,
          **overrides
        ).fetch_subscription_status(
          original_transaction_id:
            "2000000123456789"
        )
      end

    assert_includes(
      error.message,
      message
    )

    assert_empty(
      connection.requests
    )
  end

  def assert_response_error(
    status:,
    error_class:,
    message:
  )
    connection =
      fake_connection(
        status: status,
        body: "{}"
      )

    error =
      assert_raises(
        error_class
      ) do
        build_client(
          connection: connection
        ).fetch_subscription_status(
          original_transaction_id:
            "2000000123456789"
        )
      end

    assert_includes(
      error.message,
      message
    )
  end
end
