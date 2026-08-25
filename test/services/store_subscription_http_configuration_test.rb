require "test_helper"

class StoreSubscriptionHttpConfigurationTest < ActiveSupport::TestCase
  test "uses safe default timeouts" do
    environment = {}

    assert_equal(
      5.0,
      StoreSubscriptionHttpConfiguration.open_timeout(
        environment: environment
      )
    )

    assert_equal(
      15.0,
      StoreSubscriptionHttpConfiguration.read_timeout(
        environment: environment
      )
    )
  end

  test "accepts configured timeouts" do
    environment = {
      "STORE_SUBSCRIPTION_OPEN_TIMEOUT_SECONDS" => "4.5",
      "STORE_SUBSCRIPTION_READ_TIMEOUT_SECONDS" => "20"
    }

    assert_equal(
      4.5,
      StoreSubscriptionHttpConfiguration.open_timeout(
        environment: environment
      )
    )

    assert_equal(
      20.0,
      StoreSubscriptionHttpConfiguration.read_timeout(
        environment: environment
      )
    )
  end

  test "rejects invalid timeout values" do
    environment = {
      "STORE_SUBSCRIPTION_OPEN_TIMEOUT_SECONDS" => "never"
    }

    assert_raises(
      StoreSubscriptionHttpConfiguration::ConfigurationError
    ) do
      StoreSubscriptionHttpConfiguration.open_timeout(
        environment: environment
      )
    end
  end

  test "rejects unsafe timeout values" do
    environment = {
      "STORE_SUBSCRIPTION_READ_TIMEOUT_SECONDS" => "120"
    }

    error =
      assert_raises(
        StoreSubscriptionHttpConfiguration::ConfigurationError
      ) do
        StoreSubscriptionHttpConfiguration.read_timeout(
          environment: environment
        )
      end

    assert_includes(error.message, "no more than 60")
  end
end
