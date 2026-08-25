require "test_helper"
require "openssl"

class StoreSubscriptionApiFailureHandlingTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:status, :body, keyword_init: true)

  class FakeRequest
    attr_reader :headers

    def initialize
      @headers = {}
    end
  end

  class FakeConnection
    def initialize(response)
      @response = response
    end

    def get(_path)
      request = FakeRequest.new
      yield request
      @response
    end
  end

  class FakeGoogleCredentials
    def fetch_access_token!
      { "access_token" => "access-token" }
    end
  end

  test "classifies Google rate limits as retryable request failures" do
    error =
      assert_raises(
        GooglePlayDeveloperApiClient::RateLimited
      ) do
        google_client(status: 429).fetch_subscription(
          package_name: "uk.matchmuster.app",
          purchase_token: "purchase-token"
        )
      end

    assert_kind_of(
      GooglePlayDeveloperApiClient::RequestFailed,
      error
    )
  end

  test "classifies Google server failures separately" do
    error =
      assert_raises(
        GooglePlayDeveloperApiClient::ServerError
      ) do
        google_client(status: 503).fetch_subscription(
          package_name: "uk.matchmuster.app",
          purchase_token: "purchase-token"
        )
      end

    assert_includes(error.message, "HTTP 503")
  end

  test "classifies Apple server failures separately" do
    error =
      assert_raises(
        AppleAppStoreServerApiClient::ServerError
      ) do
        apple_client(status: 503).fetch_subscription_status(
          original_transaction_id: "2000000123456789"
        )
      end

    assert_includes(error.message, "HTTP 503")
  end

  test "default provider connections have bounded timeouts" do
    environment = {
      "STORE_SUBSCRIPTION_OPEN_TIMEOUT_SECONDS" => "3",
      "STORE_SUBSCRIPTION_READ_TIMEOUT_SECONDS" => "12"
    }

    google =
      GooglePlayDeveloperApiClient.new(
        credentials: FakeGoogleCredentials.new,
        environment: environment
      )

    google_connection = google.send(:connection)

    assert_equal(3.0, google_connection.options.open_timeout)
    assert_equal(12.0, google_connection.options.timeout)
  end

  private

  def google_client(status:)
    GooglePlayDeveloperApiClient.new(
      connection:
        FakeConnection.new(
          FakeResponse.new(status: status, body: "{}")
        ),
      credentials: FakeGoogleCredentials.new
    )
  end

  def apple_client(status:)
    AppleAppStoreServerApiClient.new(
      connection:
        FakeConnection.new(
          FakeResponse.new(status: status, body: "{}")
        ),
      issuer_id: "issuer-id",
      key_id: "KEY1234567",
      private_key:
        OpenSSL::PKey::EC.generate("prime256v1").private_to_pem,
      bundle_id: "uk.matchmuster.app",
      environment: "production"
    )
  end
end
