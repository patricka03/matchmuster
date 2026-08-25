require "test_helper"

class ProductionSubscriptionConfigurationTest < ActiveSupport::TestCase
  test "production forces SSL behind the Heroku proxy" do
    configuration =
      Rails.root
        .join("config/environments/production.rb")
        .read

    assert_includes(configuration, "config.assume_ssl = true")
    assert_includes(configuration, "config.force_ssl = true")
    assert_includes(configuration, 'request.path == "/up"')
  end
end
