require "test_helper"

class GooglePlayDeveloperApiClientTest <
    ActiveSupport::TestCase
  FakeResponse =
    Struct.new(
      :status,
      :body,
      keyword_init: true
    )

  FakeRequest =
    Struct.new(
      :headers,
      keyword_init: true
    )

  class FakeConnection
    attr_reader :path,
                :headers

    def initialize(
      response: nil,
      error: nil
    )
      @response = response
      @error = error
    end

    def get(path)
      raise @error if @error

      request =
        FakeRequest.new(
          headers: {}
        )

      yield request

      @path = path
      @headers = request.headers

      @response
    end
  end

  class FakeCredentials
    attr_reader :fetch_count

    def initialize(
      token: "google-access-token",
      error: nil
    )
      @token = token
      @error = error
      @fetch_count = 0
    end

    def fetch_access_token!
      @fetch_count += 1

      raise @error if @error

      {
        "access_token" => @token
      }
    end
  end

  test "fetches and parses subscription purchase" do
    response =
      FakeResponse.new(
        status: 200,
        body: {
          subscriptionState:
            "SUBSCRIPTION_STATE_ACTIVE",
          lineItems: [
            {
              productId:
                "matchmuster_plus_monthly"
            }
          ]
        }.to_json
      )

    client, connection, credentials =
      build_client(
        response: response
      )

    result =
      client.fetch_subscription(
        package_name:
          "com.matchmuster.app",
        purchase_token:
          "purchase-token"
      )

    assert_equal(
      "SUBSCRIPTION_STATE_ACTIVE",
      result["subscriptionState"]
    )

    assert_equal(
      "/androidpublisher/v3/applications/" \
        "com.matchmuster.app/" \
        "purchases/subscriptionsv2/tokens/" \
        "purchase-token",
      connection.path
    )

    assert_equal(
      "application/json",
      connection.headers["Accept"]
    )

    assert_equal(
      "Bearer google-access-token",
      connection.headers["Authorization"]
    )

    assert_equal(
      1,
      credentials.fetch_count
    )
  end

  test "encodes package name and purchase token" do
    response =
      FakeResponse.new(
        status: 200,
        body: {}.to_json
      )

    client, connection, =
      build_client(
        response: response
      )

    client.fetch_subscription(
      package_name:
        "com.matchmuster test",
      purchase_token:
        "token/with+symbols"
    )

    assert_equal(
      "/androidpublisher/v3/applications/" \
        "com.matchmuster+test/" \
        "purchases/subscriptionsv2/tokens/" \
        "token%2Fwith%2Bsymbols",
      connection.path
    )
  end

  test "raises authentication error for unauthorized response" do
    [401, 403].each do |status|
      client, =
        build_client(
          response:
            FakeResponse.new(
              status: status,
              body: "{}"
            )
        )

      error =
        assert_raises(
          GooglePlayDeveloperApiClient::
            AuthenticationError
        ) do
          client.fetch_subscription(
            package_name:
              "com.matchmuster.app",
            purchase_token:
              "purchase-token"
          )
        end

      assert_match(
        "HTTP #{status}",
        error.message
      )
    end
  end

  test "raises not found for missing subscription" do
    client, =
      build_client(
        response:
          FakeResponse.new(
            status: 404,
            body: "{}"
          )
      )

    assert_raises(
      GooglePlayDeveloperApiClient::NotFound
    ) do
      client.fetch_subscription(
        package_name:
          "com.matchmuster.app",
        purchase_token:
          "missing-token"
      )
    end
  end

  test "raises request failed for server response" do
    client, =
      build_client(
        response:
          FakeResponse.new(
            status: 500,
            body: "{}"
          )
      )

    error =
      assert_raises(
        GooglePlayDeveloperApiClient::
          RequestFailed
      ) do
        client.fetch_subscription(
          package_name:
            "com.matchmuster.app",
          purchase_token:
            "purchase-token"
        )
      end

    assert_match(
      "HTTP 500",
      error.message
    )
  end

  test "raises request failed for invalid JSON" do
    client, =
      build_client(
        response:
          FakeResponse.new(
            status: 200,
            body: "not-json"
          )
      )

    assert_raises(
      GooglePlayDeveloperApiClient::
        RequestFailed
    ) do
      client.fetch_subscription(
        package_name:
          "com.matchmuster.app",
        purchase_token:
          "purchase-token"
      )
    end
  end

  test "raises authentication error without access token" do
    credentials =
      FakeCredentials.new(
        token: nil
      )

    client, =
      build_client(
        response:
          FakeResponse.new(
            status: 200,
            body: "{}"
          ),
        credentials: credentials
      )

    assert_raises(
      GooglePlayDeveloperApiClient::
        AuthenticationError
    ) do
      client.fetch_subscription(
        package_name:
          "com.matchmuster.app",
        purchase_token:
          "purchase-token"
      )
    end
  end

  test "wraps connection failures" do
    client, =
      build_client(
        connection_error:
          RuntimeError.new(
            "connection unavailable"
          )
      )

    error =
      assert_raises(
        GooglePlayDeveloperApiClient::
          RequestFailed
      ) do
        client.fetch_subscription(
          package_name:
            "com.matchmuster.app",
          purchase_token:
            "purchase-token"
        )
      end

    assert_match(
      "connection unavailable",
      error.message
    )
  end

  private

  def build_client(
    response: nil,
    credentials: nil,
    connection_error: nil
  )
    credentials ||=
      FakeCredentials.new

    connection =
      FakeConnection.new(
        response: response,
        error: connection_error
      )

    client =
      GooglePlayDeveloperApiClient.new(
        connection: connection,
        credentials: credentials
      )

    [
      client,
      connection,
      credentials
    ]
  end
end
